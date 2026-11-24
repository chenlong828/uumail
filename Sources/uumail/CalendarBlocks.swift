import MailDomain
import Presentation
import SwiftUI

/// One month-grid chip. Selection is a highlight only; the AppKit click catcher decides
/// single (select) versus double (open) because SwiftUI's tap gestures fire both.
struct CalendarChipView: View {
    let chip: CalendarChip
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            Text(chip.title)
                .scaledInheritedFont(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(chip.isAllDay ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
            ClickCatcher(onSingleClick: onSelect, onDoubleClick: onOpen)
        }
    }
}

/// One week-timeline block. Position and lane geometry stay here so the calendar view only
/// loops over columns.
struct CalendarWeekBlockView: View {
    let block: WeekBlock
    let isSelected: Bool
    let laneCount: Int
    let startHour: Int
    let columnWidth: CGFloat
    let hourHeight: CGFloat
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let width = (columnWidth - 6) / CGFloat(max(1, laneCount))
        ZStack(alignment: .topLeading) {
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
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.35)
                    : Color.accentColor.opacity(0.2)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            ClickCatcher(onSingleClick: onSelect, onDoubleClick: onOpen)
        }
        .offset(
            x: CGFloat(block.lane) * width + 2,
            y: CGFloat(block.startMinute - startHour * 60) / 60 * hourHeight
        )
    }
}

/// Inline error banner above the grid (a load failure keeps the last projection).
struct CalendarBanner: View {
    let text: String

    var body: some View {
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
}
