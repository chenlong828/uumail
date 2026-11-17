import AppKit
import MailDomain
import Presentation
import SwiftUI

struct MailboxView: View {
    @Bindable var viewModel: MailboxViewModel
    @State private var compose: ComposeViewModel?
    @State private var searchText = ""
    @FocusState private var messageListFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(viewModel.folders, id: \.serverID, selection: folderSelection) { folder in
                Label(folder.displayName, systemImage: icon(for: folder.type))
                    .scaledInheritedFont(.body)
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
            // A SwiftUI window's scenePhase stays `.active` when the app is deactivated on
            // macOS (measured 2026-11-14), so foreground state comes from NSApplication:
            // the view only forwards, the view model owns the timer rule.
            .onAppear { viewModel.setApplicationActive(NSApp.isActive) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.setApplicationActive(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                viewModel.setApplicationActive(false)
            }
            .toolbar {
                MailboxToolbar(
                    state: MailboxToolbar.State(
                        hasSelection: viewModel.selectedMessage != nil,
                        allowsRemoteContent: viewModel.allowsRemoteContent,
                        canAllowRemoteContent: viewModel.canAllowRemoteContent,
                        canMarkSelectedRead: viewModel.canMarkSelectedRead,
                        isSyncing: viewModel.sync.phase == .syncing
                    ),
                    actions: MailboxToolbar.Actions(
                        newMessage: { compose = viewModel.composeNew() },
                        reply: { compose = viewModel.composeReply() },
                        replyAll: { compose = viewModel.composeReplyAll() },
                        forward: { compose = viewModel.composeForward() },
                        setAllowRemoteContent: { viewModel.setAllowsRemoteContent($0) },
                        markSelectedRead: { viewModel.markSelectedRead() },
                        refresh: { Task { await viewModel.refresh() } }
                    )
                )
            }
            .sheet(item: $compose) { draft in
                ComposeView(viewModel: draft, onClose: { compose = nil })
            }
        } detail: {
            MessageBodyView(
                header: viewModel.headerPresentation,
                bodyPresentation: viewModel.body,
                notice: viewModel.bodyNotice,
                attachments: viewModel.attachments,
                allowRemoteContent: viewModel.allowsRemoteContent,
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
            get: { viewModel.selectedListKey },
            set: { listKey in
                if let listKey { viewModel.select(listKey: listKey) }
            }
        )
    }

    private var messageList: some View {
        List(selection: messageSelection) {
            ForEach(viewModel.visibleMessages, id: \.listKey) { message in
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
                .tag(message.listKey)
            }
        }
        .focusable()
        .focused($messageListFocused)
        .onDeleteCommand {
            Task { await viewModel.deleteSelected() }
        }
        .onKeyPress(.delete) {
            // Fallback for hosts where List does not consume Delete; the VM single-flight
            // guard makes a duplicate delivery harmless.
            guard messageListFocused else { return .ignored }
            Task { await viewModel.deleteSelected() }
            return .handled
        }
        .overlay {
            if viewModel.visibleMessages.isEmpty {
                EmptyState(
                    title: viewModel.sync.phase == .syncing ? "正在同步…" : "没有邮件",
                    systemImage: "tray"
                )
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let deleteError = viewModel.deleteErrorText {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(deleteError).lineLimit(1)
            } else if let markReadError = viewModel.markReadErrorText {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(markReadError).lineLimit(1)
            } else {
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
            }
            Spacer()
            Text("\(viewModel.visibleMessages.count) 封")
                // 225% truncates the status text; the count must stay visible.
                .layoutPriority(1)
        }
        .scaledFont(.caption)
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


private extension Message {
    /// Folder + server id: search results can contain the same server id in two folders.
    var listKey: String { MailboxViewModel.listKey(for: self) }
}
