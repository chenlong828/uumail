import AppKit
import Foundation
import WebKit

// L2 layout probe for REQ-0027 / SCN-0021. Compiles the production
// Sources/uumail/MessageBodyStyle.swift, loads synthetic Outlook-shaped tables and measures
// document vs. viewport width. Run with:
//   swiftc -module-cache-path /tmp/uumail-mcache \
//     -Xcc -fmodules-cache-path=/tmp/uumail-mcache \
//     Sources/uumail/MessageBodyStyle.swift \
//     doc/history/works/2026-11-23-table-adapt/evidence/TableLayoutProbe.swift \
//     -o /tmp/TableLayoutProbe && /tmp/TableLayoutProbe

struct Case {
    let name: String
    let viewport: CGFloat
    let html: String
    let check: (ProbeResult) -> String?
}

struct ProbeResult {
    var documentWidth: Int
    var clientWidth: Int
    var tableWidth: Int
    var tableScrollWidth: Int
    var tableClientWidth: Int
    var imageWidth: Int
    var imageCellWidth: Int
    var headers: [String]
}

let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

func wideTableHTML(_ width: Int) -> String {
    let columns = ["序号", "产品线", "总文档", "价值生产资产", "配套过程资产", "变更总数", "产品类", "开发类", "测试类"]
    let header = columns.map { "<th width=\"\(width / columns.count)\">\($0)</th>" }.joined()
    let row = (1...6).map { index in
        "<tr><td>\(index)</td><td>O4.5</td><td>4780</td><td>4765</td><td>15</td><td>168</td><td>11</td><td>52</td><td>105</td></tr>"
    }.joined()
    return """
    <html><head></head><body>
    <p>指标表</p>
    <table class="MsoNormalTable" width="\(width)" style="width:\(width)px; border-collapse:collapse" border="1">
    <thead><tr>\(header)</tr></thead><tbody>\(row)</tbody></table>
    <p>表后文字</p>
    </body></html>
    """
}

func narrowTableHTML() -> String {
    """
    <html><head></head><body>
    <table width="300" style="width:300px; border-collapse:collapse" border="1">
    <tr><td width="120">名称</td><td width="180">说明</td></tr>
    <tr><td>A</td><td>一段文字</td></tr>
    </table>
    </body></html>
    """
}

func imageTableHTML() -> String {
    """
    <html><head></head><body>
    <table width="900" style="width:900px; border-collapse:collapse" border="1">
    <tr>
      <td width="600" style="width:600px"><img src="data:image/png;base64,\(png1x1)" width="600"></td>
      <td width="300" style="width:300px"><p>右侧文字说明列，用来观察压缩后的可读性。</p></td>
    </tr>
    </table>
    </body></html>
    """
}

func wideCase(_ name: String, viewport: CGFloat, width: Int, expectTableWidth: Int?) -> Case {
    Case(name: name, viewport: viewport, html: wideTableHTML(width)) { result in
        if result.documentWidth > Int(viewport) + 1 {
            return "document \(result.documentWidth) > viewport \(Int(viewport))"
        }
        if let expectTableWidth, abs(result.tableWidth - expectTableWidth) > 2 {
            return "table \(result.tableWidth) != \(expectTableWidth)"
        }
        if result.headers.count != 9 {
            return "expected 9 header cells, got \(result.headers.count)"
        }
        return nil
    }
}

let cases: [Case] = [
    wideCase("wideTableAtDefaultSize", viewport: 978, width: 816, expectTableWidth: 816),
    wideCase("wideTableAtLargeSizes/145", viewport: 810, width: 816, expectTableWidth: nil),
    wideCase("wideTableAtLargeSizes/175", viewport: 671, width: 816, expectTableWidth: nil),
    wideCase("wideTableAtLargeSizes/225", viewport: 522, width: 816, expectTableWidth: nil),
    Case(name: "narrowTableKeepsWidth", viewport: 978, html: narrowTableHTML()) { result in
        if result.documentWidth > 979 { return "document \(result.documentWidth) > viewport 978" }
        if abs(result.tableWidth - 300) > 2 { return "narrow table stretched to \(result.tableWidth)" }
        return nil
    },
    Case(name: "imageTableFitsViewport", viewport: 668, html: imageTableHTML()) { result in
        if result.documentWidth > 669 { return "document \(result.documentWidth) > viewport 668" }
        if result.imageWidth > result.imageCellWidth + 1 {
            return "image \(result.imageWidth) > cell \(result.imageCellWidth)"
        }
        return nil
    },
]

final class Runner: NSObject, WKNavigationDelegate {
    private var index = 0
    private var failures = 0
    private var webView: WKWebView!

    func start() {
        load(index)
    }

    private func load(_ index: Int) {
        let item = cases[index]
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: item.viewport, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(
            MessageBodyStyle.sanitized(item.html, allowRemoteContent: false),
            baseURL: nil
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
          const table = document.querySelector('table');
          const tr = table.getBoundingClientRect();
          const img = document.querySelector('img');
          const cell = img ? img.closest('td') : null;
          return JSON.stringify({
            documentWidth: document.documentElement.scrollWidth,
            clientWidth: document.documentElement.clientWidth,
            tableWidth: Math.round(tr.width),
            tableScrollWidth: table.scrollWidth,
            tableClientWidth: table.clientWidth,
            imageWidth: img ? Math.round(img.getBoundingClientRect().width) : 0,
            imageCellWidth: cell ? Math.round(cell.getBoundingClientRect().width) : 0,
            headers: Array.from(table.querySelectorAll('th')).map(th => th.textContent.trim())
          });
        })()
        """
        webView.evaluateJavaScript(js) { value, error in
            let item = cases[self.index]
            if let error {
                print("FAIL \(item.name): JS error \(error)")
                self.failures += 1
            } else if let json = value as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let result = ProbeResult(
                    documentWidth: object["documentWidth"] as? Int ?? 0,
                    clientWidth: object["clientWidth"] as? Int ?? 0,
                    tableWidth: object["tableWidth"] as? Int ?? 0,
                    tableScrollWidth: object["tableScrollWidth"] as? Int ?? 0,
                    tableClientWidth: object["tableClientWidth"] as? Int ?? 0,
                    imageWidth: object["imageWidth"] as? Int ?? 0,
                    imageCellWidth: object["imageCellWidth"] as? Int ?? 0,
                    headers: object["headers"] as? [String] ?? []
                )
                if let problem = item.check(result) {
                    print("FAIL \(item.name): \(problem) \(json)")
                    self.failures += 1
                } else {
                    print("PASS \(item.name) \(json)")
                }
            } else {
                print("FAIL \(item.name): no measurement")
                self.failures += 1
            }
            self.index += 1
            if self.index < cases.count {
                self.load(self.index)
            } else {
                print("RESULT \(cases.count - self.failures)/\(cases.count) passed")
                exit(self.failures == 0 ? 0 : 1)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner()
runner.start()
app.run()
