import Foundation
import MailDomain
import UserNotifications

/// System notification poster. A refused permission degrades silently: mail still
/// syncs, only the banner is missing.
public struct SystemNotifier: Notifier {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func postNewMail(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "uumail"
        content.body = "\(count) 封新邮件"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
