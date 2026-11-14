import AppKit
import Presentation
import SwiftUI

struct MailboxView: View {
    @Bindable var viewModel: MailboxViewModel
    @State private var compose: ComposeViewModel?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(viewModel.folders, id: \.serverID, selection: folderSelection) { folder in
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
            .navigationTitle(currentFolderName)
            .navigationSplitViewColumnWidth(min: 280, ideal: 380)
            .searchable(text: $searchText, placement: .toolbar, prompt: "搜索邮件")
            .onChange(of: searchText) { _, query in
                Task { await viewModel.search(query) }
            }
            .onChange(of: viewModel.selection.searchQuery) { _, query in
                if searchText != query { searchText = query }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        compose = viewModel.composeNew()
                    } label: {
                        Label("新建", systemImage: "square.and.pencil")
                    }
                    Button {
                        compose = viewModel.composeReply()
                    } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    .disabled(viewModel.selectedMessage == nil)
                    Button {
                        compose = viewModel.composeReplyAll()
                    } label: {
                        Label("全部回复", systemImage: "arrowshape.turn.up.left.2")
                    }
                    .disabled(viewModel.selectedMessage == nil)
                    Button {
                        compose = viewModel.composeForward()
                    } label: {
                        Label("转发", systemImage: "arrowshape.turn.up.right")
                    }
                    .disabled(viewModel.selectedMessage == nil)
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.sync.phase == .syncing)
                }
            }
            .sheet(item: $compose) { draft in
                ComposeView(viewModel: draft, onClose: { compose = nil })
            }
        } detail: {
            MessageBodyView(
                bodyPresentation: viewModel.body,
                notice: viewModel.bodyNotice,
                attachments: viewModel.attachments,
                onRetry: { Task { await viewModel.openSelected() } },
                onOpenAttachment: { attachment in
                    if let url = await viewModel.download(attachment) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            .navigationTitle("阅读")
        }
    }

    private var currentFolderName: String {
        viewModel.folders.first { $0.serverID == viewModel.selection.folderID }?.displayName ?? "收件箱"
    }

    private var folderSelection: Binding<String?> {
        Binding(
            get: { viewModel.selection.folderID },
            set: { folderID in
                if let folderID { viewModel.select(folderID: folderID) }
            }
        )
    }

    private var messageSelection: Binding<String?> {
        Binding(
            get: { viewModel.selection.messageID },
            set: { messageID in
                if let messageID { viewModel.select(messageID: messageID) }
            }
        )
    }

    private var messageList: some View {
        List(selection: messageSelection) {
            ForEach(viewModel.messages, id: \.serverID) { message in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(message.isRead ? Color.clear : Color.accentColor)
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.subject ?? "(无主题)")
                            .fontWeight(message.isRead ? .regular : .semibold)
                            .lineLimit(1)
                        Text(DisplayFormat.senderName(message.sender))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(DisplayFormat.messageDate(message.receivedRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(message.serverID)
            }
        }
        .overlay {
            if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    viewModel.sync.phase == .syncing ? "正在同步…" : "没有邮件",
                    systemImage: "tray"
                )
            }
        }
    }

    private var statusBar: some View {
        HStack {
            switch viewModel.sync.phase {
            case .idle:
                Text(viewModel.sync.lastSyncedAt.map { "上次同步 \(DisplayFormat.timestamp($0))" } ?? "就绪")
            case .syncing:
                ProgressView().controlSize(.small)
                Text("同步中…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).lineLimit(1)
            }
            Spacer()
            Text("\(viewModel.messages.count) 封")
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
}
