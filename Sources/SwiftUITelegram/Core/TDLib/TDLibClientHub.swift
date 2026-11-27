import Foundation
import TDLibKit

/// Owns the single process-wide `TDLibClientManager` instance that polls `td_receive`
/// on one thread and demultiplexes updates across all concurrent multi-account `TDLibClient` sessions.
final class TDLibClientHub {
    private let manager: TDLibClientManager
    private let lock = NSLock()
    private var hasConfiguredLogLevel = false

    init() {
        self.manager = TDLibClientManager()
    }

    func createClient(updateHandler: @escaping (Data, TDLibClient) -> Void) -> TDLibClient {
        let client = manager.createClient(updateHandler: updateHandler)

        lock.lock()
        let shouldConfigureLog = !hasConfiguredLogLevel
        hasConfiguredLogLevel = true
        lock.unlock()

        if shouldConfigureLog {
            // Keep TDLib's internal C++ stdout logging quiet (1 = errors only).
            let verbosity = SetLogVerbosityLevel(newVerbosityLevel: 1)
            _ = try? client.execute(query: DTO(verbosity, encoder: client.encoder))
        }

        return client
    }

    /// Gracefully closes all active TDLib clients across all logged-in accounts on app termination.
    func closeAllClients() {
        manager.closeClients()
    }
}
