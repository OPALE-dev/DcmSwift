import Foundation

/// Transient PS3.18 8.10 notification connections. Subscriptions live in the UPS index.
public actor DICOMUPSEventHub {
    public struct Connection: Sendable {
        public let id: UUID
        public let events: AsyncThrowingStream<Data, Error>
    }
    private struct Listener {
        let ae: String
        let continuation: AsyncThrowingStream<Data, Error>.Continuation
    }
    private var listeners: [UUID: Listener] = [:]
    private var messageID: UInt16 = 0
    public init() {}

    public func connect(ae: String, bufferLimit: Int = 64) -> Connection {
        let id = UUID()
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(max(1, bufferLimit))) { continuation in
            listeners[id] = Listener(ae: ae, continuation: continuation)
            continuation.onTermination = { @Sendable _ in Task { await self.disconnect(id) } }
        }
        return Connection(id: id, events: stream)
    }

    public func disconnect(_ id: UUID) {
        listeners.removeValue(forKey: id)?.continuation.finish()
    }
    public func isConnected(_ ae: String) -> Bool { listeners.values.contains { $0.ae == ae } }
    public func connectedAEs() -> [String] { Array(Set(listeners.values.map(\.ae))).sorted() }

    func publish(to ae: String, uid: String, type: UInt16, information: DataSet) throws {
        messageID = messageID == .max ? 1 : messageID + 1
        var object = try DICOMJSON.object(information)
        object["00000002"] = ["vr": "UI", "Value": [DICOMSOPClass.upsEvent]]
        object["00000110"] = ["vr": "US", "Value": [Int(messageID)]]
        object["00001000"] = ["vr": "UI", "Value": [uid]]
        object["00001002"] = ["vr": "US", "Value": [Int(type)]]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        for (id, listener) in listeners where listener.ae == ae {
            if case .dropped = listener.continuation.yield(data) {
                listener.continuation.finish(throwing: DICOMwebHTTPError(503, "notification consumer is too slow"))
                listeners.removeValue(forKey: id)
            }
        }
    }
}
