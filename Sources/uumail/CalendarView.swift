import MailDomain
import Presentation
import SwiftUI

/// The calendar page (SCN-0024): month grid and week timeline over the meetings the user
/// received by mail. Every interaction is local; nothing here touches the network.
struct CalendarView: View {
    @Bindable var model: CalendarViewModel
    var onOpenMail: (String, String) -> Void

    @State private var detail: SelectedOccurrence?
    @State private var exportFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let errorText = model.errorText {
                banner(errorText)
            }
            content
        }
        .navigationTitle("日历")
        .task { await model.activate() }
        .sheet(item: $detail) { item in
            detailSheet(item.occurrence)
        }
        .alert("无法生成日历文件", isPresented: $exportFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请稍后重试，或先打开来源邮件。")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.mode == .month ? model.month.title : model.week.title)
                .scaledFont(.title2).fontWeight(.semibold)
            Spacer()
            Picker("视图", selection: modeBinding) {
                Text("月").tag(CalendarViewModel.Mode.month)
                Text("周").tag(CalendarViewModel.Mode.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            Button {
                Task { await model.showPrevious() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("上一周期")
            Button("今天") {
                Task { await model.showToday() }
            }
            Button {
                Task { await model.showNext() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("下一周期")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modeBinding: Binding<CalendarViewModel.Mode> {
        Binding(
            get: { model.mode },
            set: { mode in Task { await model.setMode(mode) } }
        )
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
            Spacer()
        }
        .scaledInheritedFont(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.15))
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.occurrences.isEmpty {
            ProgressView("正在加载日历…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.occurrences.isEmpty {
            EmptyState(
                title: "本期没有会议",
                systemImage: "calendar",
                description: "日历只展示升级后新收到的会议邀请。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.mode == .month {
            monthGrid
        } else {
            weekGrid
        }
    }

    // MARK: - Month

    private var monthGrid: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                ForEach(model.month.daySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .scaledInheritedFont(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            ForEach(Array(model.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 1) {
                    ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                        monthCell(day)
                    }
                }
            }
            if model.isTruncated {
                Text("仅显示前 500 条会议")
                    .scaledInheritedFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .padding(8)
    }

    private func monthCell(_ day: MonthDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .scaledInheritedFont(.caption)
                .foregroundStyle(day.isInMonth ? (day.isToday ? Color.accentColor : Color.primary) : Color.secondary)
                .fontWeight(day.isToday ? .bold : .regular)
            ForEach(Array(day.chips.enumerated()), id: \.offset) { _, chip in
                Button {
                    detail = SelectedOccurrence(occurrence: chip.occurrence)
                } label: {
                    Text(chip.title)
                        .scaledInheritedFont(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(chip.isAllDay ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
            }
            if day.hiddenCount > 0 {
                Text("+\(day.hiddenCount)")
                    .scaledInheritedFont(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(day.isInMonth ? Color.clear : Color.secondary.opacity(0.06))
        .border(Color.secondary.opacity(0.15))
    }

    // MARK: - Week

    private var weekGrid: some View {
        GeometryReader { proxy in
            let hourHeight: CGFloat = 48
            let gutter: CGFloat = 44
            let columnWidth = max(1, (proxy.size.width - gutter) / 7)
            let totalHeight = CGFloat(model.week.endHour - model.week.startHour) * hourHeight

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: gutter)
                    ForEach(Array(model.week.days.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 1) {
                            Text(dayLabel(column.date))
                                .scaledInheritedFont(.caption)
                                .foregroundStyle(column.isToday ? Color.accentColor : .secondary)
                            ForEach(Array(model.week.allDayChips.enumerated()), id: \.offset) { _, chip in
                                if Calendar.current.isDate(chip.start, inSameDayAs: column.date) {
                                    Text(chip.title)
                                        .scaledInheritedFont(.caption2)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 3)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
                .padding(.bottom, 4)

                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(model.week.startHour..<model.week.endHour, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour))
                                    .scaledInheritedFont(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: gutter, height: hourHeight, alignment: .topTrailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        ForEach(Array(model.week.days.enumerated()), id: \.offset) { _, column in
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(model.week.startHour..<model.week.endHour, id: \.self) { _ in
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.08))
                                            .frame(height: hourHeight)
                                    }
                                }
                                ForEach(Array(column.blocks.enumerated()), id: \.offset) { _, block in
                                    let laneCount = max(1, (column.blocks.map(\.lane).max() ?? 0) + 1)
                                    let width = (columnWidth - 6) / CGFloat(laneCount)
                                    Button {
                                        detail = SelectedOccurrence(occurrence: block.occurrence)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(block.title)
                                                .scaledInheritedFont(.caption2)
                                                .lineLimit(1)
                                            Text(String(format: "%02d:%02d", block.startMinute / 60, block.startMinute % 60))
                                                .scaledInheritedFont(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(3)
                                        .frame(width: width - 2, alignment: .topLeading)
                                        .frame(height: max(18, CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight - 2), alignment: .topLeading)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(
                                        x: CGFloat(block.lane) * width + 2,
                                        y: CGFloat(block.startMinute - model.week.startHour * 60) / 60 * hourHeight
                                    )
                                }
                            }
                            .frame(width: columnWidth, height: totalHeight, alignment: .topLeading)
                            .border(Color.secondary.opacity(0.1))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E d"
        return formatter.string(from: date)
    }

    // MARK: - Detail

    private func detailSheet(_ occurrence: MeetingOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(occurrence.subject ?? "会议")
                .scaledFont(.title3).fontWeight(.semibold)
            Label(timeRange(occurrence), systemImage: "clock")
            if let location = occurrence.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            if let organizer = occurrence.organizer, !organizer.isEmpty {
                Label(DisplayFormat.senderName(organizer), systemImage: "person")
            }
            Spacer()
            HStack {
                Button("在日历中打开") {
                    guard let text = model.icsText(for: occurrence) else {
                        exportFailed = true
                        return
                    }
                    if !CalendarExport.present(text, uid: occurrence.uid) {
                        exportFailed = true
                    }
                }
                Spacer()
                Button("打开邮件") {
                    let source = (occurrence.folderID, occurrence.serverID)
                    detail = nil
                    onOpenMail(source.0, source.1)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 240)
    }

    private func timeRange(_ occurrence: MeetingOccurrence) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        if occurrence.isAllDay {
            formatter.dateFormat = "M月d日"
            return "\(formatter.string(from: occurrence.start)) 全天"
        }
        let end = DateFormatter()
        end.locale = Locale(identifier: "zh_CN")
        end.dateFormat = "HH:mm"
        return "\(formatter.string(from: occurrence.start))–\(end.string(from: occurrence.end))"
    }
}

private struct SelectedOccurrence: Identifiable {
    let id = UUID()
    let occurrence: MeetingOccurrence
}
