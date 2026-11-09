import Foundation
import UserNotifications

public protocol NotificationPosting: Sendable {
    func requestAuthorization() async
    func post(title: String, body: String) async
}

/// System notification poster. Permission refusal degrades silently: mail still syncs.
public struct SystemNotificationPoster: NotificationPosting {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
