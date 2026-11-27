import MailDomain
import SwiftUI

/// Left column of the drafts tab (REQ-0043). Rows are newest first (the view model keeps
/// the store order); selecting a row opens the editor in the reading pane.
struct DraftListView: View {
    let drafts: [DraftRecord]
    @Binding var selection: String?
    /// Destructive delete: the view model removes the row (and tombstones the server copy).
    var onDelete: (DraftRecord) -> Void = { _ in }

    private static let timeFormat = DateFormatter()

    var body: some View {
        List(selection: $selection) {
            ForEach(drafts) { draft in
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.subject.isEmpty ? "无主题" : draft.subject)
                        .lineLimit(1)
                        .font(.body)
                    HStack(spacing: 6) {
                        Text(draft.to.isEmpty ? "未填写收件人" : draft.to)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Self.timeText(draft.updatedAt))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(draft.id)
                .id(draft.id)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(draft.subject.isEmpty ? "无主题" : draft.subject)，"
                    + (draft.to.isEmpty ? "未填写收件人" : draft.to)
                )
                .contextMenu {
                    Button("删除草稿", role: .destructive) { onDelete(draft) }
                }
            }
        }
        .overlay {
            if drafts.isEmpty {
                EmptyState(
                    title: "没有草稿",
                    systemImage: "square.and.pencil",
                    description: "撰写页里「存草稿」后，会出现在这里。"
                )
            }
        }
        .onDeleteCommand {
            guard let id = selection, let draft = drafts.first(where: { $0.id == id }) else {
                return
            }
            onDelete(draft)
        }
        .navigationTitle("草稿箱")
        .navigationSplitViewColumnWidth(min: 320, ideal: 480)
    }

    static func timeText(_ date: Date) -> String {
        if timeFormat.dateFormat.isEmpty {
            timeFormat.dateFormat = "MM-dd HH:mm"
        }
        return timeFormat.string(from: date)
    }
}
