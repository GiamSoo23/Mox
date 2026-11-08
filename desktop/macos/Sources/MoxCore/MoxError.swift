import Foundation

/// Errors a person can act on, with messages written for them.
public enum MoxError: LocalizedError, Equatable {
    case upload(String)
    case tooLarge(Int64)
    case signInFailed
    case notOwner
    case schemaMismatch(Int)
    case invalidRow(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .upload(let message):
            return message
        case .tooLarge(let size):
            return "\(humanSize(size)) is too big: Mox sends files up to 50 MB."
        case .signInFailed:
            return "Couldn't sign in to your Supabase project. Check the Mox user's email and password."
        case .notOwner:
            return "Signed in, but this user isn't the owner of Mox in this project (mox.meta.owner_id)."
        case .schemaMismatch(let version):
            return "Your Supabase project has Mox schema v\(version), but this app needs v2. "
                + "Apply the latest migrations."
        case .invalidRow(let reason):
            return "The current file in your project isn't valid: \(reason)."
        case .http(let status, let body):
            return "Supabase answered HTTP \(status): \(body)"
        }
    }
}
