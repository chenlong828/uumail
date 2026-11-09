import AppKit
import AppServices
import MailStore
import SyncEngine
import SwiftUI

struct MailboxView: View {
    @Bindable var model: MailboxModel
    @State private var compose: ComposeModel?

    var body: some View {
        NavigationSplitView {
            List(model.folders, id: \.serverID, selection: $model.selectedFolderID) { folder in
                Label(folder.displayName, systemImage: icon(for: folder.type))
                    .tag(folder.serverID)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("文件夹")
        } content: {
            VStack(spacing: 0) {
                messageList
                Divider()
                statusBar
            }
            .navigationTitle(model.folders.first(where: { $0.serverID == model.selectedFolderID })?.displayName ?? "收件箱")
            .navigationSplitViewColumnWidth(min: 280, ideal: 380)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        compose = ComposeModel(mode: .new)
                    } label: {
                        Label("新建", systemImage: "square.and.pencil")
                    }
                    Button {
                        reply()
                    } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    .disabled(selectedMessage == nil)
                    Button {
                        forward()
                    } label: {
                        Label("转发", systemImage: "arrowshape.turn.up.right")
                    }
                    .disabled(selectedMessage == nil)
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.state == .syncing)
                }
            }
            .sheet(item: $compose) { draft in
                ComposeView(
                    compose: draft,
                    service: model.sendService ?? NullSendService(),
                    onClose: { compose = nil }
                )
            }
        } detail: {
            MessageBodyView(
                state: model.detailState,
                attachments: model.attachments,
                onRetry: { Task { await model.loadBody() } },
                onOpenAttachment: { attachment in
                    if let url = try? await model.downloadAttachment(attachment) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            .navigationTitle("阅读")
        }
    }

    private var selectedMessage: StoredMessage? {
        model.messages.first { $0.serverID == model.selectedMessageID }
    }

    private func reply() {
        guard let message = selectedMessage else { return }
        let html: String? = {
            if case .loaded(let html) = model.detailState { return html }
            return nil
        }()
        compose = ComposeModel.replySeed(sender: message.sender, subject: message.subject, html: html)
    }

    private func forward() {
        guard let message = selectedMessage else { return }
        let html: String? = {
            if case .loaded(let html) = model.detailState { return html }
            return nil
        }()
        compose = ComposeModel.forwardSeed(subject: message.subject, html: html)
    }

    private var messageList: some View {
        List(selection: $model.selectedMessageID) {
            ForEach(model.messages, id: \.serverID) { message in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(message.isRead ? Color.clear : Color.accentColor)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.subject ?? "(无主题)")
                        .fontWeight(message.isRead ? .regular : .semibold)
                        .lineLimit(1)
                    Text(Self.senderName(message.sender))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(Self.displayDate(message.receivedRaw))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(message.serverID)
            }
        }
        .overlay {
            if model.messages.isEmpty {
                ContentUnavailableView(
                    model.state == .syncing ? "正在同步…" : "没有邮件",
                    systemImage: "tray"
                )
            }
        }
    }

    private var statusBar: some View {
        HStack {
            switch model.state {
            case .idle:
                Text(model.lastSyncedAt.map { "上次同步 \(Self.localTime($0))" } ?? "就绪")
            case .syncing:
                ProgressView().controlSize(.small)
                Text("同步中…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).lineLimit(1)
            }
            Spacer()
            Text("\(model.messages.count) 封")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func icon(for type: Int) -> String {
        switch type {
        case 2: "tray.full"
        case 3: "doc.text"
        case 4: "trash"
        case 5: "paperplane"
        case 6: "tray.and.arrow.up"
        case 8: "person.crop.circle"
        case 11: "calendar"
        default: "folder"
        }
    }

    /// `"张三" <zhang@corp.com>` → `张三`; a bare address stays as is.
    private static func senderName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let angle = raw.firstIndex(of: "<") else { return raw }
        let name = raw[..<angle].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? raw : name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func displayDate(_ raw: String?) -> String {
        guard let raw else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: raw) else { return String(raw.prefix(16)) }
        let output = DateFormatter()
        output.dateFormat = "MM-dd HH:mm"
        return output.string(from: date)
    }
}

private final class NullSendService: MailSendService, @unchecked Sendable {
    func send(_ draft: MailDraft) async throws -> String { throw MailGatewayError.unsupported }
    func saveDraft(_ draft: MailDraft) throws -> String { throw MailGatewayError.unsupported }
}
