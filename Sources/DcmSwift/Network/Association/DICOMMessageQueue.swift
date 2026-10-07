import NIOConcurrencyHelpers

/// A bounded single-consumer queue of messages with back-pressure: `push`
/// waits while the buffer is full, so a slow consumer slows the network
/// reader instead of growing memory. A consumer that stops listening makes
/// further pushes drop their message.
final class DICOMMessageQueue: @unchecked Sendable {
    private struct State {
        var buffer: [DICOMMessage] = []
        var end: Result<Void, Error>?
        var abandoned = false
        var consumer: CheckedContinuation<DICOMMessage?, Error>?
        var producers: [CheckedContinuation<Void, Never>] = []
    }

    private let capacity: Int
    private let state = NIOLockedValueBox(State())

    init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// Delivers a message, waiting while the buffer is full.
    func push(_ message: DICOMMessage) async {
        enum Step {
            case delivered(CheckedContinuation<DICOMMessage?, Error>?)
            case dropped
            case full
        }
        while true {
            let step: Step = state.withLockedValue { state in
                if state.abandoned || state.end != nil { return .dropped }
                if let consumer = state.consumer {
                    state.consumer = nil
                    return .delivered(consumer)
                }
                if state.buffer.count < capacity {
                    state.buffer.append(message)
                    return .delivered(nil)
                }
                return .full
            }
            switch step {
            case .delivered(let consumer):
                consumer?.resume(returning: message)
                return
            case .dropped:
                return
            case .full:
                await withCheckedContinuation { (producer: CheckedContinuation<Void, Never>) in
                    let ready = state.withLockedValue { state -> Bool in
                        if state.abandoned || state.end != nil || state.buffer.count < capacity { return true }
                        state.producers.append(producer)
                        return false
                    }
                    if ready { producer.resume() }
                }
            }
        }
    }

    /// Ends the queue; the consumer receives the buffered messages, then
    /// the end or the error.
    func finish(throwing error: Error? = nil) {
        let (consumer, producers): (CheckedContinuation<DICOMMessage?, Error>?, [CheckedContinuation<Void, Never>]) =
            state.withLockedValue { state in
                guard state.end == nil else { return (nil, []) }
                state.end = error.map { .failure($0) } ?? .success(())
                let producers = state.producers
                state.producers = []
                guard state.buffer.isEmpty, let consumer = state.consumer else { return (nil, producers) }
                state.consumer = nil
                return (consumer, producers)
            }
        producers.forEach { $0.resume() }
        if let consumer {
            if let error { consumer.resume(throwing: error) } else { consumer.resume(returning: nil) }
        }
    }

    /// The consumer no longer listens: buffered and later messages are
    /// dropped.
    func abandon() {
        let producers = state.withLockedValue { state -> [CheckedContinuation<Void, Never>] in
            state.abandoned = true
            state.buffer = []
            let producers = state.producers
            state.producers = []
            return producers
        }
        producers.forEach { $0.resume() }
    }

    /// The next message, or nil at the end.
    func next() async throws -> DICOMMessage? {
        try await withCheckedThrowingContinuation { (consumer: CheckedContinuation<DICOMMessage?, Error>) in
            let outcome: (Result<DICOMMessage?, Error>?, CheckedContinuation<Void, Never>?) = state.withLockedValue { state in
                if !state.buffer.isEmpty {
                    let message = state.buffer.removeFirst()
                    let producer = state.producers.isEmpty ? nil : state.producers.removeFirst()
                    return (.success(message), producer)
                }
                if let end = state.end {
                    switch end {
                    case .success: return (.success(nil), nil)
                    case .failure(let error): return (.failure(error), nil)
                    }
                }
                state.consumer = consumer
                return (nil, nil)
            }
            outcome.1?.resume()
            if let result = outcome.0 { consumer.resume(with: result) }
        }
    }
}
