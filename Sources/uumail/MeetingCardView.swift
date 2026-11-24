import Presentation
import SwiftUI

/// Read-only meeting card between the envelope header and the body (SCN-0023).
struct MeetingCardView: View {
    let card: MeetingCardPresentation
    let onOpenInCalendar: () -> Void
    /// The floating reader shows the card read-only (SCN-0025): its toolbar owns the
    /// calendar export, so the card must not repeat the button.
    var showsAction: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.time)
                    .scaledFont(.headline)
                HStack(spacing: 12) {
                    if let location = card.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    if let organizer = card.organizer {
                        Label(organizer, systemImage: "person")
                    }
                }
                .scaledInheritedFont(.callout)
                .foregroundStyle(.secondary)
                if let recurrence = card.recurrence {
                    Text(recurrence)
                        .scaledInheritedFont(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if showsAction {
                Button("在日历中打开", action: onOpenInCalendar)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
        .accessibilityElement(children: .contain)
    }
}
