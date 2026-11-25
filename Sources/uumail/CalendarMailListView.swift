import MailDomain
import MeetingDomain
import Presentation
import SwiftUI

/// Calendar page's left column (REQ-0040): the visible range's invitation emails, in the
/// same row style as the inbox/outbox list. A single click selects the source mail's first
/// visible occurrence (highlighting the calendar block); a double click opens the floating
/// reader, matching the block entry.
struct CalendarMailListView: View {
    @Bindable var model: CalendarViewModel

    private var selectedID: String? {
        model.selectedOccurrence.map {
            "\($0.folderID)\u{1F}\($0.serverID)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(model.invitationMails) { item in
                        CalendarMailRow(item: item)
                            .id(item.id)
                            .listRowBackground(
                                item.id == selectedID
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.clear
                            )
                            .overlay {
                                MessageRowClick(
                                    onSelect: { model.select(item.occurrence) },
                                    onOpen: { CalendarReader.open(item.occurrence, model: model) }
                                )
                            }
                    }
                }
                .overlay {
                    if model.invitationMails.isEmpty {
                        EmptyState(
                            title: model.isLoading
                                ? "正在加载日历…"
                                : (model.occurrences.isEmpty ? "本期没有会议邀请" : "没有可显示的邀请邮件"),
                            systemImage: "calendar"
                        )
                    }
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Divider()
            statusBar
        }
    }

    private var statusBar: some View {
        HStack {
            if let error = model.errorText {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1)
            } else {
                Text("\(model.invitationMails.count) 封会议邀请")
            }
            Spacer()
        }
        .scaledFont(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// One invitation-email row: subject, sender and received time, matching `MessageRowView`.
private struct CalendarMailRow: View {
    let item: CalendarMailItem

    private static let dayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static func meetingLabel(_ occurrence: MeetingOccurrence) -> String {
        let day = dayTime.string(from: occurrence.start)
        return occurrence.isAllDay ? String(day.prefix(5)) + " 全天" : day
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .scaledInheritedFont(.body)
                    .lineLimit(1)
                Text(item.senderText)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Self.meetingLabel(item.occurrence))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
