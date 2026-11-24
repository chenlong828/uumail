import MailDomain
import Presentation
import SwiftUI
import MeetingDomain

/// The calendar page (SCN-0024): month grid and week timeline over the meetings the user
/// received by mail. Every interaction is local; nothing here touches the network.
///
/// Interaction (REQ-0032): a single click selects a block (highlight only, no detail
/// sheet); a double click, Return or Space opens the source invitation in the floating
/// reader (`SCN-0025`). The reader's calendar toolbar offers 转发 and 在日历中打开.
struct CalendarView: View {
    @Bindable var model: CalendarViewModel

    @State private var selectedKey: String?
    @State private var exportFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let errorText = model.errorText {
                CalendarBanner(text: errorText)
            }
            content
        }
        .navigationTitle("日历")
        .task { await model.activate() }
        .focusable()
        .onKeyPress(.return) { openSelectedOccurrence() }
        .onKeyPress(.space) { openSelectedOccurrence() }
        .onKeyPress(.escape) {
            guard selectedKey != nil else { return .ignored }
            selectedKey = nil
            return .handled
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
                monthChip(chip, isSelected: key(for: chip.occurrence) == selectedKey)
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

    private func monthChip(_ chip: CalendarChip, isSelected: Bool) -> some View {
        CalendarChipView(
            chip: chip,
            isSelected: isSelected,
            onSelect: { selectedKey = key(for: chip.occurrence) },
            onOpen: { open(chip.occurrence) }
        )
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
                                let laneCount = max(1, (column.blocks.map(\.lane).max() ?? 0) + 1)
                                ForEach(Array(column.blocks.enumerated()), id: \.offset) { _, block in
                                    CalendarWeekBlockView(
                                        block: block,
                                        isSelected: key(for: block.occurrence) == selectedKey,
                                        laneCount: laneCount,
                                        startHour: model.week.startHour,
                                        columnWidth: columnWidth,
                                        hourHeight: hourHeight,
                                        onSelect: { selectedKey = key(for: block.occurrence) },
                                        onOpen: { open(block.occurrence) }
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

    // MARK: - Selection & opening

    /// Stable identity of one occurrence: the same meeting can appear on several days.
    private func key(for occurrence: MeetingOccurrence) -> String {
        "\(occurrence.uid)\u{1F}\(occurrence.start.timeIntervalSince1970)"
    }

    private func open(_ occurrence: MeetingOccurrence) {
        selectedKey = key(for: occurrence)
        let coordinator = ReaderCoordinator.shared
        coordinator.show(
            folderID: occurrence.folderID,
            serverID: occurrence.serverID,
            geometry: coordinator.geometry(readingPaneWidth: nil),
            style: .calendar,
            openInCalendar: { openInCalendar(occurrence) }
        )
    }

    /// Return / Space act on the selected block, mirroring the list's Enter/Space.
    private func openSelectedOccurrence() -> KeyPress.Result {
        guard let key = selectedKey, let occurrence = occurrence(withKey: key) else { return .ignored }
        open(occurrence)
        return .handled
    }

    private func occurrence(withKey key: String) -> MeetingOccurrence? {
        let candidates = model.mode == .month
            ? model.month.weeks.flatMap { $0.days.flatMap { $0.chips.map(\.occurrence) } }
            : model.week.days.flatMap { $0.blocks.map(\.occurrence) }
        return candidates.first { self.key(for: $0) == key }
    }

    private func openInCalendar(_ occurrence: MeetingOccurrence) {
        guard let text = model.icsText(for: occurrence) else {
            exportFailed = true
            return
        }
        if !CalendarExport.present(text, uid: occurrence.uid) {
            exportFailed = true
        }
    }
}
