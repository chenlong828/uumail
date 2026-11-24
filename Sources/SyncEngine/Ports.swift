import Foundation
import MailDomain
import SyncContract

// Transitional names kept for callers that have not migrated yet (T-1110-02+).
// The ports themselves live in `MailDomain` (`MailGateway`, `SyncStore`).
public typealias AccountRef = AccountID
public typealias MailGatewayError = MailError
