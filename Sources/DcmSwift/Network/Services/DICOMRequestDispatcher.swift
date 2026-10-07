import Foundation
import Logging

/// Performs the requests a peer sends on an association: C-ECHO, C-STORE,
/// C-FIND, C-MOVE, and C-GET, through the configured services. A service
/// error becomes a failure status; it never ends the association.
struct DICOMRequestDispatcher: Sendable {
    var verification = true
    var storage: DICOMStorageService?
    var query: DICOMQueryService?
    var retrieve: DICOMRetrieveService?
    /// Opens associations to C-MOVE destinations.
    var moveClient: DICOMClient?

    func perform(_ request: DICOMMessage, on association: DICOMAssociation) async {
        await handle(request, on: association)
        await association.runtime.finishedPerforming(request.command.messageID ?? 0)
    }

    private func handle(_ request: DICOMMessage, on association: DICOMAssociation) async {
        let runtime = association.runtime
        let command = request.command
        let id = command.messageID ?? 0
        guard let context = association.negotiated.presentationContexts[request.presentationContextID] else { return }
        // Requests come from the side allowed to be SCU on this context.
        let allowed = runtime.role == .acceptor ? context.requestorIsSCU : context.requestorIsSCP
        let serviceContext = DICOMServiceContext(
            callingAETitle: association.negotiated.callingAETitle, calledAETitle: association.negotiated.calledAETitle,
            remoteAddress: association.remoteAddress, userIdentity: association.negotiated.userIdentity,
            presentationContext: context, cancelled: { await runtime.isCancelled(id) })

        func respond(_ status: DICOMStatus, comment: String? = nil, dataSet: DICOMDataSetPayload? = nil,
                     progress: DICOMRetrieveProgress? = nil) async {
            var response = DICOMCommand(field: command.field.response, hasDataSet: dataSet != nil)
            response.messageIDBeingRespondedTo = id
            response.affectedSOPClassUID = command.affectedSOPClassUID ?? command.requestedSOPClassUID
            response.affectedSOPInstanceUID = command.affectedSOPInstanceUID
            response.status = status.code
            response.errorComment = comment.map { String($0.prefix(64)) }
            if let progress {
                if status.isPending { response.remainingSuboperations = UInt16(clamping: progress.remaining) }
                response.completedSuboperations = UInt16(clamping: progress.completed)
                response.failedSuboperations = UInt16(clamping: progress.failed)
                response.warningSuboperations = UInt16(clamping: progress.warning)
            }
            do {
                try await runtime.send(DICOMMessage(
                    presentationContextID: request.presentationContextID, command: response, dataSet: dataSet))
            } catch {
                runtime.logger.debug("cannot answer \(command.field): \(error)")
            }
        }
        func comment(_ error: Error) -> String { "\(error)" }

        guard allowed else {
            await respond(.unrecognizedOperation, comment: "role not negotiated for this SOP class")
            return
        }

        switch command.field {
        case .cEchoRequest where verification:
            await respond(.success)

        case .cStoreRequest:
            guard let storage, let payload = request.dataSet, let sopClass = command.affectedSOPClassUID,
                  let sopInstance = command.affectedSOPInstanceUID else {
                await respond(storage == nil ? .sopClassNotSupported : .storageCannotUnderstand)
                return
            }
            let instance = DICOMReceivedInstance(
                sopClassUID: sopClass, sopInstanceUID: sopInstance, transferSyntaxUID: context.transferSyntax,
                payload: payload, moveOriginatorAETitle: command.moveOriginatorAETitle,
                moveOriginatorMessageID: command.moveOriginatorMessageID,
                sourceAETitle: runtime.role == .acceptor
                    ? association.negotiated.callingAETitle : association.negotiated.calledAETitle)
            do {
                await respond(try await storage.store(instance, context: serviceContext))
            } catch {
                runtime.logger.warning("storing \(sopInstance) failed: \(error)")
                await respond(.storageCannotUnderstand, comment: comment(error))
            }

        case .cFindRequest:
            guard let query, let payload = request.dataSet else {
                await respond(query == nil ? .sopClassNotSupported : .identifierDoesNotMatchSOPClass)
                return
            }
            do {
                let identifier = try DICOMDataSetCoding.decode(payload.data(), transferSyntax: context.transferSyntax)
                let matches = try await query.find(
                    identifier, informationModel: context.abstractSyntax, context: serviceContext)
                for try await match in matches {
                    if await serviceContext.isCancelled {
                        await respond(.cancel)
                        return
                    }
                    let encoded = try DICOMDataSetCoding.encode(match, transferSyntax: context.transferSyntax)
                    await respond(.pending, dataSet: DICOMDataSetPayload(data: encoded))
                }
                await respond(await serviceContext.isCancelled ? .cancel : .success)
            } catch {
                runtime.logger.warning("C-FIND failed: \(error)")
                await respond(.unableToProcess, comment: comment(error))
            }

        case .cMoveRequest, .cGetRequest:
            guard let retrieve, let payload = request.dataSet else {
                await respond(retrieve == nil ? .sopClassNotSupported : .identifierDoesNotMatchSOPClass)
                return
            }
            do {
                let identifier = try DICOMDataSetCoding.decode(payload.data(), transferSyntax: context.transferSyntax)
                let items = try await retrieve.retrieve(
                    identifier, informationModel: context.abstractSyntax, context: serviceContext)
                if command.field == .cMoveRequest {
                    guard let destinationTitle = command.moveDestination,
                          let destination = await retrieve.destination(for: destinationTitle), let moveClient else {
                        await respond(.moveDestinationUnknown)
                        return
                    }
                    try await moveClient.withAssociation(
                        to: destination, presentationContexts: DICOMPresentationContextProposal.proposals(for: items)
                    ) { outgoing in
                        await subOperations(items, through: outgoing, moveOriginator: (
                            association.negotiated.callingAETitle, id), respond: respond, context: serviceContext)
                    }
                } else {
                    await subOperations(items, through: association, moveOriginator: nil, respond: respond,
                                        context: serviceContext)
                }
            } catch {
                runtime.logger.warning("\(command.field) failed: \(error)")
                await respond(.unableToProcess, comment: comment(error))
            }

        default:
            await respond(.unrecognizedOperation)
        }
    }

    /// Sends the instances by C-STORE, reporting progress after each
    /// (PS3.4 C.4.2.3, C.4.3.3).
    private func subOperations(
        _ items: [DICOMRetrieveItem], through association: DICOMAssociation, moveOriginator: (String, UInt16)?,
        respond: (DICOMStatus, String?, DICOMDataSetPayload?, DICOMRetrieveProgress?) async -> Void,
        context: DICOMServiceContext
    ) async {
        var progress = DICOMRetrieveProgress(remaining: items.count)
        var failedInstances: [String] = []
        for item in items {
            if await context.isCancelled {
                await respond(.cancel, nil, failureList(failedInstances, context), progress)
                return
            }
            progress.remaining -= 1
            do {
                let status = try await association.store(item, moveOriginator: moveOriginator)
                switch status.category {
                case .success: progress.completed += 1
                case .warning: progress.warning += 1
                default:
                    progress.failed += 1
                    failedInstances.append(item.sopInstanceUID)
                }
            } catch {
                progress.failed += 1
                failedInstances.append(item.sopInstanceUID)
            }
            if progress.remaining > 0 { await respond(.pending, nil, nil, progress) }
        }
        let status: DICOMStatus
        if progress.failed > 0, progress.failed == items.count {
            status = .retrieveOutOfResourcesForSuboperations
        } else if progress.failed + progress.warning > 0 {
            status = .suboperationsCompleteWithFailures
        } else {
            status = .success
        }
        await respond(status, nil, failureList(failedInstances, context), progress)
    }

    /// The Failed SOP Instance UID List (0008,0058) of a final response.
    private func failureList(_ uids: [String], _ context: DICOMServiceContext) -> DICOMDataSetPayload? {
        guard !uids.isEmpty else { return nil }
        let dataSet = DataSet()
        _ = dataSet.set(value: uids.joined(separator: "\\"), forTagName: "FailedSOPInstanceUIDList")
        return (try? DICOMDataSetCoding.encode(dataSet, transferSyntax: context.presentationContext.transferSyntax))
            .map(DICOMDataSetPayload.init(data:))
    }
}
