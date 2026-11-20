import Foundation
import TDLibKit

enum TDLibErrorHelper {
    /// Returns true when TDLib reports 404 (for example, `loadChats` reached the end of the chat list).
    static func isNotFound(_ error: any Swift.Error) -> Bool {
        if let tdError = error as? TDLibKit.Error {
            return tdError.code == 404
        }
        return false
    }

    /// Formats an error for display in the UI.
    /// Per TDLib specification, error code 406 must never be shown verbatim to the user.
    static func userFacingMessage(for error: any Swift.Error) -> String? {
        if let tdError = error as? TDLibKit.Error {
            if tdError.code == 406 {
                return nil
            }
            return "\(tdError.message) (code \(tdError.code))"
        }
        return error.localizedDescription
    }
}
