import SwiftUI

/// The compose sheet's format bar. Buttons are non-focusable so clicking one does not
/// take the first responder away from the WebView and the current selection survives.
struct ComposeFormatBar: View {
    let handle: ComposeEditorHandle

    private let sizes = [13, 16, 20, 24]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                commandButton("bold", help: "加粗") { handle.perform(.bold) }
                commandButton("italic", help: "斜体") { handle.perform(.italic) }
                commandButton("underline", help: "下划线") { handle.perform(.underline) }
                commandButton("strikethrough", help: "删除线") { handle.perform(.strike) }

                divider

                Menu {
                    ForEach(sizes, id: \.self) { size in
                        Button("\(size) pt") { handle.perform(.fontSize(size)) }
                    }
                } label: {
                    Label("字号", systemImage: "textformat.size")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("字号")

                divider

                commandButton("text.alignleft", help: "左对齐") { handle.perform(.alignLeft) }
                commandButton("text.aligncenter", help: "居中") { handle.perform(.alignCenter) }
                commandButton("text.alignright", help: "右对齐") { handle.perform(.alignRight) }

                divider

                commandButton("list.bullet", help: "项目符号") { handle.perform(.unorderedList) }
                commandButton("list.number", help: "编号列表") { handle.perform(.orderedList) }

                divider

                commandButton("eraser", help: "清除格式") { handle.perform(.clearFormat) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    private var divider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }

    private func commandButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
