import Foundation
import Logging

/// Performs the requests a peer sends on an association: C-ECHO, C-STORE,
/// C-FIND, C-MOVE, C-GET, and DIMSE-N, through the configured services. A
/// service error becomes a failure status; it never ends the association.
struct DICOMRequestDispatcher: Sendable {
    var verification = true
    var storage: DICOMStorageService?
    var query: DICOMQueryService?
    /// Answers C-FIND on the Modality Worklist Information Model.
    var worklist: DICOMQueryService?
    var retrieve: DICOMRetrieveService?
    /// DIMSE-N services, by abstract syntax.
    var normalized: [String: DICOMNormalizedService] = [:]
    var storageCommitment: DICOMStorageCommitmentService?
    var commitmentReceiver: DICOMStorageCommitmentReceiver?
    /// Opens associations to C-MOVE destinations and Storage Commitment
    /// SCUs.
    var outgoingClient: DICOMClient?

    func perform(_ request: DICOMMessage, on association: DICOMAssociation) async {
        await handle(request, on: association)
        await association.runtime.finishedPerforming(request.command.messageID ?? 0)
    }

    private func handle(_ request: DICOMMessage, on association: DICOMAssociation) async {
        let runtime = association.runtime
        let command = request.command
        let id = command.messageID ?? 0
        guard let context = association.negotiated.presentationContexts[request.presentationContextID] else { return }
        // Requests come from the side allowed to be SCU on this context,
        // notifications from the SCP. A requestor that sends a notification
        // without having negotiated the SCP role is tolerated.
        let allowed: Bool
        if command.field == .nEventReportRequest {
            allowed = runtime.role == .acceptor || context.requestorIsSCU
        } else {
            allowed = runtime.role == .acceptor ? context.requestorIsSCU : context.requestorIsSCP
        }
        let serviceContext = DICOMServiceContext(
            callingAETitle: association.negotiated.callingAETitle, calledAETitle: association.negotiated.calledAETitle,
            remoteAddress: association.remoteAddress, userIdentity: association.negotiated.userIdentity,
            presentationContext: context, peerCertificate: runtime.peerCertificate,
            moveDestination: command.moveDestination, cancelled: { await runtime.isCancelled(id) })

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
            let query = context.abstractSyntax == DICOMSOPClass.modalityWorklistFind ? worklist : self.query
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
            } catch let error as DICOMServiceError {
                await respond(error.status, comment: error.comment)
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
                          let destination = await retrieve.destination(for: destinationTitle),
                          let outgoingClient else {
                        await respond(.moveDestinationUnknown)
                        return
                    }
                    try await outgoingClient.withAssociation(
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

        case _ where DICOMNormalizedOperation(command) != nil:
            await performNormalized(request, on: association, context: serviceContext)

        default:
            await respond(.unrecognizedOperation)
        }
    }

    // MARK: DIMSE-N

    private func performNormalized(
        _ request: DICOMMessage, on association: DICOMAssociation, context: DICOMServiceContext
    ) async {
        let runtime = association.runtime
        let command = request.command
        let operation = DICOMNormalizedOperation(command)!
        let sopClass = command.affectedSOPClassUID ?? command.requestedSOPClassUID ?? ""
        let sopInstance = command.affectedSOPInstanceUID ?? command.requestedSOPInstanceUID
        let syntax = context.presentationContext.transferSyntax

        func respond(_ response: DICOMNormalizedResponse) async {
            var answer = DICOMCommand(field: command.field.response, hasDataSet: response.dataSet != nil)
            answer.messageIDBeingRespondedTo = command.messageID
            answer.affectedSOPClassUID = response.sopClassUID ?? sopClass
            answer.affectedSOPInstanceUID = response.sopInstanceUID ?? sopInstance
            answer.status = response.status.code
            answer.errorComment = response.errorComment.map { String($0.prefix(64)) }
            answer.errorID = response.errorID
            answer.attributeIdentifierList = response.attributes
            if response.status.category != .failure {
                switch operation {
                case .eventReport(let type): answer.eventTypeID = response.typeID ?? type
                case .action(let type): answer.actionTypeID = response.typeID ?? type
                default: break
                }
            }
            do {
                let payload = try response.dataSet.map {
                    DICOMDataSetPayload(data: try DICOMDataSetCoding.encode($0, transferSyntax: syntax))
                }
                answer.hasDataSet = payload != nil
                try await runtime.send(DICOMMessage(
                    presentationContextID: request.presentationContextID, command: answer, dataSet: payload))
            } catch {
                runtime.logger.debug("cannot answer \(command.field): \(error)")
            }
        }

        let normalizedRequest = DICOMNormalizedRequest(
            operation: operation, sopClassUID: sopClass, sopInstanceUID: sopInstance, payload: request.dataSet,
            transferSyntaxUID: syntax)
        do {
            if context.presentationContext.abstractSyntax == DICOMSOPClass.storageCommitmentPushModel {
                switch operation {
                case .action(1) where storageCommitment != nil:
                    await commitStorage(
                        normalizedRequest, on: association, context: context, respond: respond)
                    return
                case .eventReport(let type) where type == 1 || type == 2:
                    guard let dataSet = try normalizedRequest.dataSet() else {
                        await respond(DICOMNormalizedResponse(status: .missingAttribute, errorComment: "no Event Information"))
                        return
                    }
                    let result = try DICOMStorageCommitmentResult(dataSet: dataSet)
                    try await commitmentReceiver?.received(result, context: context)
                    // Answer before waking the operation waiting for the
                    // result, which may release the association at once.
                    await respond(DICOMNormalizedResponse(status: .success))
                    await runtime.deliverCommitment(result)
                    return
                default:
                    break
                }
            }
            guard let service = normalized[context.presentationContext.abstractSyntax] else {
                switch operation {
                case .eventReport: await respond(DICOMNormalizedResponse(status: .noSuchEventType))
                case .action: await respond(DICOMNormalizedResponse(status: .noSuchActionType))
                default: await respond(DICOMNormalizedResponse(status: .unrecognizedOperation))
                }
                return
            }
            await respond(try await service.perform(normalizedRequest, context: context))
        } catch let error as DICOMServiceError {
            await respond(DICOMNormalizedResponse(status: error.status, errorComment: error.comment))
        } catch {
            runtime.logger.warning("\(command.field) failed: \(error)")
            await respond(DICOMNormalizedResponse(status: .processingFailure, errorComment: "\(error)"))
        }
    }

    /// Storage Commitment SCP (PS3.4 J.3.2.2, J.3.3.2): answer the N-ACTION,
    /// then send the result once known.
    private func commitStorage(
        _ request: DICOMNormalizedRequest, on association: DICOMAssociation, context: DICOMServiceContext,
        respond: (DICOMNormalizedResponse) async -> Void
    ) async {
        guard request.sopInstanceUID == DICOMSOPClass.storageCommitmentPushModelInstance else {
            await respond(DICOMNormalizedResponse(status: .noSuchObjectInstance))
            return
        }
        let commitment: DICOMStorageCommitmentRequest
        do {
            guard let dataSet = try request.dataSet() else {
                await respond(DICOMNormalizedResponse(status: .missingAttribute, errorComment: "no Action Information"))
                return
            }
            commitment = try DICOMStorageCommitmentRequest(dataSet: dataSet)
        } catch {
            await respond(DICOMNormalizedResponse(status: .invalidArgumentValue, errorComment: "\(error)"))
            return
        }
        await respond(DICOMNormalizedResponse(status: .success))

        // The requestor may release as soon as it has the response: the
        // result is computed and sent outside the request, so that the
        // release does not wait for it.
        guard let service = storageCommitment else { return }
        let client = outgoingClient
        let logger = association.runtime.logger
        // The N-ACTION is answered: nothing cancels the commitment.
        let context = DICOMServiceContext(
            callingAETitle: context.callingAETitle, calledAETitle: context.calledAETitle,
            remoteAddress: context.remoteAddress, userIdentity: context.userIdentity,
            presentationContext: context.presentationContext, peerCertificate: context.peerCertificate,
            cancelled: { false })
        Task {
            var result: DICOMStorageCommitmentResult
            do {
                result = try await service.commit(commitment, context: context)
                result.transactionUID = commitment.transactionUID
            } catch {
                logger.warning("Storage Commitment \(commitment.transactionUID) failed: \(error)")
                result = .failure(of: commitment, reason: DICOMStorageCommitmentResult.FailureReason.processingFailure)
            }
            await Self.report(result, on: association, client: client, service: service, context: context)
        }
    }

    /// Sends a Storage Commitment result on the association if it is still
    /// open, else on a new one to the SCU, with the SCP role.
    static func report(
        _ result: DICOMStorageCommitmentResult, on association: DICOMAssociation, client: DICOMClient?,
        service: DICOMStorageCommitmentService, context: DICOMServiceContext
    ) async {
        let logger = association.runtime.logger
        func send(on association: DICOMAssociation) async throws {
            let response = try await association.nEventReport(
                sopClassUID: DICOMSOPClass.storageCommitmentPushModel,
                sopInstanceUID: DICOMSOPClass.storageCommitmentPushModelInstance, eventTypeID: result.eventTypeID,
                information: result.dataSet())
            if response.status.category == .failure {
                logger.warning("the SCU answered the Storage Commitment result with \(response.status)")
            }
        }
        if await association.runtime.acceptsRequests {
            do {
                try await send(on: association)
                return
            } catch {
                logger.debug("Storage Commitment result not sent on the same association: \(error)")
            }
        }
        guard let client, let destination = await service.destination(for: context.callingAETitle) else {
            logger.warning("no address for \(context.callingAETitle): Storage Commitment result \(result.transactionUID) not sent")
            return
        }
        do {
            try await client.withAssociation(
                to: destination,
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.storageCommitmentPushModel]),
                roleSelections: [DICOMRoleSelection(
                    sopClassUID: DICOMSOPClass.storageCommitmentPushModel, scuRole: false, scpRole: true)]
            ) { try await send(on: $0) }
        } catch {
            logger.warning("Storage Commitment result \(result.transactionUID) not sent to \(destination.aeTitle): \(error)")
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
