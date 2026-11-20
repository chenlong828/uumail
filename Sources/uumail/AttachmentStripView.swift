import MailDomain
import SwiftUI

/// The attachment strip in the reading pane. It only presents and forwards: it never
/// downloads, reads files or maps `MailError`. Single click selects, double click/Return
/// opens, and the context menu offers 打开/另存为… (REQ-0026 / SCN-0020).
struct AttachmentStripView: View {
    let attachments: [Attachment]
    /// `saveErrorText ?? attachmentErrorText` from the host; nil means no banner.
    let errorText: String?
    /// Set only while the panel/copy stage is running for that attachment.
    let savingID: String?
    let onOpen: (Attachment) async -> Void
    let onSave: (Attachment) async -> Void
    let onCancelSave: () -> Void

    @State private var selectedAttachmentID: String?
    @FocusState private var focusedAttachmentID: String?

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        row(for: attachment)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                banner
            }
            .onChange(of: attachments) { _, _ in
                selectedAttachmentID = nil
                focusedAttachmentID = nil
            }
        }
    }

    private func row(for attachment: Attachment) -> some View {
        Button {
            // Single click only selects. Double click fires this twice; the action is
            // idempotent and never opens, so the double-click gesture stays unambiguous.
            selectedAttachmentID = attachment.id
            focusedAttachmentID = attachment.id
        } label: {
            Label(attachment.displayName, systemImage: "paperclip")
                .scaledInheritedFont(.body)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .overlay {
            if selectedAttachmentID == attachment.id {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task { await onOpen(attachment) }
            }
        )
        .focusable()
        .focused($focusedAttachmentID, equals: attachment.id)
        .onKeyPress(.return) {
            Task { await onOpen(attachment) }
            return .handled
        }
        .contextMenu {
            Button("打开") { Task { await onOpen(attachment) } }
            Button("另存为…") { Task { await onSave(attachment) } }
        }
        .accessibilityLabel(attachment.displayName)
        .accessibilityHint("双击打开；右键可另存为")
        .accessibilityAction(named: Text("打开")) {
            Task { await onOpen(attachment) }
        }
        .accessibilityAction(named: Text("另存为…")) {
            Task { await onSave(attachment) }
        }
    }

    /// One line below the strip: saving takes precedence over an older error. With neither
    /// there is no view at all, so the 100% layout is unchanged.
    @ViewBuilder
    private var banner: some View {
        if let savingID, attachments.contains(where: { $0.id == savingID }) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在另存为…")
                Button("取消", action: onCancelSave)
                    .buttonStyle(.link)
                Spacer()
            }
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        } else if let errorText {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(errorText)
                Spacer()
            }
            .scaledFont(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}
