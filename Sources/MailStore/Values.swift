import Foundation
import MailDomain

// Transitional names: the canonical values now live in `MailDomain` (T-1110-01).
// Call sites migrate off these aliases in later tasks of W-SCN-REFACTOR.
public typealias AccountID = MailDomain.AccountID
public typealias MailFolder = MailDomain.Folder
public typealias StoredFolder = MailDomain.Folder
public typealias MailAttachment = MailDomain.Attachment
public typealias StoredAttachment = MailDomain.Attachment
public typealias MailMessage = MailDomain.Message
public typealias StoredMessage = MailDomain.Message
public typealias MailDraft = MailDomain.Draft
public typealias StoredOutboxItem = MailDomain.OutboxItem

public struct NewAccount: Sendable {
    public var displayName: String
    public var address: String
    public var host: String

    public init(displayName: String, address: String, host: String) {
        self.displayName = displayName
        self.address = address
        self.host = host
    }
}

public enum MailStoreError: Error, Equatable, Sendable {
    case folderNotFound(account: AccountID, folder: String)
    case accountNotFound(AccountID)
    case invalidFolder(reason: String)
    case database(String)
}
