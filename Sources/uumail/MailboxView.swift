import AppKit
import MailDomain
import Presentation
import SwiftUI

@MainActor
struct MailboxView: View {
    @Bindable var viewModel: MailboxViewModel
    /// Present in the running app; nil in probes that only host the mail side.
    var calendarModel: CalendarViewModel?
    @State var section: MailboxSection = .inbox
    @State private var attachmentActions: AttachmentActionModel
    @State var compose: ComposeViewModel?
    /// Drafts tab: the editor continued in the reading pane (REQ-0043) and its list row.
    @State var draftCompose: ComposeViewModel?
    @State var selectedDraftID: String?
    @State private var searchText = ""
    /// Selection that came from a mouse click must not scroll itself to the center (a
    /// scroll between the two clicks would move the row out from under the pointer).
    @State private var clickSelectionKey: String?
    /// The reading pane's current size; the compose sheet matches it (REQ-0021).
    @State var readingPaneSize = CGSize(width: 720, height: 560)
    @FocusState private var messageListFocused: Bool

    init(viewModel: MailboxViewModel, calendarModel: CalendarViewModel? = nil) {
        _viewModel = Bindable(wrappedValue: viewModel)
        self.calendarModel = calendarModel
        _attachmentActions = State(initialValue: AttachmentActionModel(
            currentKey: { viewModel.selectedListKey },
            download: { await viewModel.download($0) }
        ))
    }

    var body: some View {
        mailSplit
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            sectionToolbar
            mailboxToolbar
        }
        .background(ToolbarTooltipInstaller().frame(width: 0, height: 0))
        .onChange(of: section) { _, value in switchSection(to: value) }
        // A SwiftUI window's scenePhase stays `.active` when the app is deactivated on
        // macOS (measured 2026-11-14), so foreground state comes from NSApplication:
        // the view only forwards, the view model owns the timer rule.
        .onAppear {
            viewModel.setApplicationActive(NSApp.isActive)
            ReaderCoordinator.shared.attach(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.setApplicationActive(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            viewModel.setApplicationActive(false)
        }
    }

    private func switchSection(to value: MailboxSection) {
        // Leaving the drafts tab keeps the editor's text: auto-save first (REQ-0043).
        if section == .drafts, value != .drafts { leaveDraftEditor() }
        switch value {
        case .inbox:
            if let id = viewModel.inboxFolderID {
                viewModel.select(folderID: id)
            }
        case .sent:
            Task {
                await viewModel.selectSent()
                // A quick switch away while the Sent sync is in flight must win.
                if section != .sent, let id = viewModel.inboxFolderID {
                    viewModel.select(folderID: id)
                }
            }
        case .drafts:
            viewModel.refreshDrafts()
        case .calendar:
            break
        }
    }

    private var mailSplit: some View {
        NavigationSplitView {
            if section == .calendar, let calendarModel {
                CalendarMailListView(model: calendarModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 480)
            } else if section == .drafts {
                draftListColumn
            } else {
                mailListColumn
                    .navigationSplitViewColumnWidth(min: 320, ideal: 480)
            }
        } detail: {
            if section == .calendar, let calendarModel {
                CalendarView(model: calendarModel)
            } else if section == .drafts {
                draftDetail
            } else {
                mailReadingPane
            }
        }
        // Covers internal selection changes (refresh auto-select, delete, clear); the list
        // binding setter covers the user click synchronously. Both are idempotent.
        .onChange(of: viewModel.selectedListKey) { _, _ in
            attachmentActions.syncSelection()
        }
    }

    private var mailListColumn: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            statusBar
        }
        .navigationTitle(currentFolderName)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索邮件")
        .onChange(of: searchText) { _, query in
            Task { await viewModel.search(query) }
        }
        .onChange(of: viewModel.selection.searchQuery) { _, query in
            if searchText != query { searchText = query }
        }
        .sheet(item: $compose) { draft in
            ComposeView(
                viewModel: draft,
                preferredWidth: readingPaneSize.width,
                preferredHeight: readingPaneSize.height,
                allowRemoteContent: viewModel.allowsRemoteContent,
                onClose: {
                compose = nil
                if section == .drafts { viewModel.loadDrafts() }
            }
            )
        }
    }

    private var mailReadingPane: some View {
        GeometryReader { proxy in
            MessageBodyView(
                header: viewModel.headerPresentation,
                meetingCard: viewModel.meetingCard,
                onOpenInCalendar: openMeetingInCalendar,
                bodyPresentation: viewModel.body,
                inlineImageHTML: viewModel.inlineImageHTML,
                notice: viewModel.bodyNotice,
                attachments: viewModel.attachments,
                allowRemoteContent: viewModel.allowsRemoteContent,
                onRetry: { Task { await viewModel.openSelected() } },
                attachmentErrorText: attachmentActions.saveErrorText
                    ?? viewModel.attachmentErrorText,
                savingAttachmentID: attachmentActions.visibleSavingID,
                onOpenAttachment: { await attachmentActions.open($0) },
                onSaveAttachment: { attachment in attachmentActions.startSave(attachment) },
                onCancelSave: { attachmentActions.cancelSave() }
            )
            .onAppear { readingPaneSize = proxy.size }
            .onChange(of: proxy.size) { _, size in readingPaneSize = size }
        }
        .navigationTitle("阅读")
    }

    private func openMeetingInCalendar() {
        guard let uid = viewModel.meetingInvite?.uid,
              let calendarModel,
              let text = calendarModel.icsText(uid: uid)
        else { return }
        _ = CalendarExport.present(text, uid: uid)
    }

    private var currentFolderName: String {
        section == .sent ? "发件箱" : "收件箱"
    }

    private var messageSelection: Binding<String?> {
        Binding(
            get: { viewModel.selectedListKey },
            set: { listKey in
                if let listKey {
                    clickSelectionKey = listKey
                    viewModel.select(listKey: listKey)
                }
                attachmentActions.syncSelection()
            }
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
        List(selection: messageSelection) {
            ForEach(viewModel.visibleMessages, id: \.listKey) { message in
                MessageRowView(message: message)
                    .tag(message.listKey)
                    .id(message.listKey)
                    .overlay {
                        MessageRowClick(
                            onSelect: {
                                messageSelection.wrappedValue = message.listKey
                                messageListFocused = true
                            },
                            onOpen: { openReader(message) }
                        )
                    }
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
        .onKeyPress(.return) {
            guard messageListFocused, viewModel.selectedMessage != nil else { return .ignored }
            openSelectedInReader()
            return .handled
        }
        .onKeyPress(.space) {
            guard messageListFocused, viewModel.selectedMessage != nil else { return .ignored }
            openSelectedInReader()
            return .handled
        }
        .overlay {
            if viewModel.visibleMessages.isEmpty {
                EmptyState(
                    title: viewModel.sync.phase == .syncing
                        ? "正在同步…"
                        : (section == .sent ? "没有发件邮件" : "没有邮件"),
                    systemImage: "tray"
                )
            }
        }
        .onChange(of: viewModel.selectedListKey) { _, key in
            guard let key, key != clickSelectionKey else { return }
            withAnimation { proxy.scrollTo(key, anchor: .center) }
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

}
