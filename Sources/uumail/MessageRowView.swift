import MailDomain
import Presentation
import SwiftUI

/// One message-list row (extracted from `MailboxView` so the view file keeps its line
/// budget, R71). Presentation only: the double-click entry stays on the row in
/// `MailboxView` where the list selection and the reader coordinator live.
struct MessageRowView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.accentColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.subject ?? "(无主题)")
                    .scaledInheritedFont(.body)
                    .fontWeight(message.isRead ? .regular : .semibold)
                    .lineLimit(1)
                Text(DisplayFormat.senderName(message.sender))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(DisplayFormat.messageDate(message.receivedRaw))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
