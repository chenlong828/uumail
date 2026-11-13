import Foundation
import MailDomain

// MARK: - Transitional value names

public typealias FolderSummary = MailDomain.Folder
public typealias MessageSummary = MailDomain.Message
public typealias FolderListing = MailDomain.FolderListing
public typealias MessageDelta = MailDomain.MessageDelta
public typealias SyncReport = MailDomain.SyncReport

// MARK: - State

public enum SyncState: Equatable, Sendable {
    case idle
    case syncingFolders
    case syncingMessages(folder: String)
    case failed(SyncFailure)

    public struct SyncFailure: Equatable, Sendable {
        public var error: MailError
        public var folder: String?
        /// Failed calls since the last success; drives backoff in later milestones.
        public var consecutiveFailures: Int

        public init(error: MailError, folder: String?, consecutiveFailures: Int) {
            self.error = error
            self.folder = folder
            self.consecutiveFailures = consecutiveFailures
        }
    }
}
