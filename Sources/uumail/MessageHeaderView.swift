import Presentation
import SwiftUI

/// Envelope header above the reading pane body. Renders presentation values only: no
/// `Message` fields, no address assembly, no empty-row decisions (those live in
/// `MessageHeaderPresentation`).
struct MessageHeaderView: View {
    let header: MessageHeaderPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header.subject)
                .font(.headline)
                .lineLimit(2)
            ForEach(header.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(row.value)
                        .lineLimit(row.lineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .textSelection(.enabled)  // copyable envelope + the L2 probe seam
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
