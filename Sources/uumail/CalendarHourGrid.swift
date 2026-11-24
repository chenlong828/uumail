import SwiftUI

/// One dashed line per hour boundary (REQ-0036). The old week view filled each hour slot
/// with a solid band, which read as a block of grey rather than an hour grid.
struct CalendarHourGrid: View {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let width: CGFloat

    var body: some View {
        let totalHeight = CGFloat(endHour - startHour) * hourHeight
        Path { path in
            for hour in startHour...endHour {
                let y = min(CGFloat(hour - startHour) * hourHeight, totalHeight - 0.5)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(Color.gray.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

