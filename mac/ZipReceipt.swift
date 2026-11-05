// Zip Receipt for macOS: a native window around ../index.html.
// Adds what a browser can't do: saving straight to ~/Documents/Zip_Receipt
// and writing PDFs without a print dialog. Build with ./build.sh
import Cocoa
import WebKit

struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply, WKUIDelegate, WKNavigationDelegate {
    weak var web: WKWebView?
    weak var window: NSWindow?
    var indexURL: URL?
    private var pendingReply: ((Any?, String?) -> Void)?
    private var pendingPath: String?

    let base: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Zip_Receipt", isDirectory: true)

    /// Turns "2026-07/Receipts 2026-07.pdf" into a URL inside Documents/Zip_Receipt. Rejects anything that escapes it.
    func safeURL(_ rel: String?) throws -> URL {
        guard let rel = rel, !rel.isEmpty, !rel.hasPrefix("/") else { throw BridgeError(message: "bad path") }
        let parts = rel.split(separator: "/").map(String.init)
        if parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) { throw BridgeError(message: "bad path") }
        return parts.reduce(base) { $0.appendingPathComponent($1) }
    }

    // MARK: JavaScript → native
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "bad message"); return
        }
        let fm = FileManager.default
        do {
            switch cmd {
            case "info":
                replyHandler(["folder": base.path, "platform": "mac"], nil)
            case "read":
                let url = try safeURL(body["path"] as? String)
                if fm.fileExists(atPath: url.path) {
                    replyHandler(try String(contentsOf: url, encoding: .utf8), nil)
                } else {
                    replyHandler(nil, nil)
                }
            case "write":
                let url = try safeURL(body["path"] as? String)
                guard let text = body["text"] as? String else { throw BridgeError(message: "nothing to write") }
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                replyHandler(url.path, nil)
            case "pdf":
                let url = try safeURL(body["path"] as? String)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                runPrint(to: url, landscape: body["landscape"] as? Bool ?? false, reply: replyHandler)
            case "print":
                runPrint(to: nil, landscape: body["landscape"] as? Bool ?? false, reply: replyHandler)
            case "reveal":
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                if let p = body["path"] as? String, let url = try? safeURL(p), fm.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(base)
                }
                replyHandler(true, nil)
            default:
                replyHandler(nil, "unknown command \(cmd)")
            }
        } catch {
            replyHandler(nil, error.localizedDescription)
        }
    }

    // MARK: PDF / print — prints the page's print layout (#print-root), same as the browser version
    func runPrint(to url: URL?, landscape: Bool, reply: @escaping (Any?, String?) -> Void) {
        guard let web = web, let window = window else { reply(nil, "no window"); return }
        guard pendingReply == nil else { reply(nil, "already printing"); return }
        let info: NSPrintInfo
        if let url = url {
            info = NSPrintInfo(dictionary: [.jobSavingURL: url])
            info.jobDisposition = .save
        } else {
            info = NSPrintInfo()
        }
        info.paperSize = NSSize(width: 595.28, height: 841.89)          // A4
        info.orientation = landscape ? .landscape : .portrait
        let margin: CGFloat = landscape ? 22.7 : 34.0                       // 8 mm / 12 mm, matches the page CSS
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        let op = web.printOperation(with: info)
        op.showsPrintPanel = (url == nil)
        op.showsProgressPanel = false
        op.view?.frame = web.bounds
        pendingReply = reply
        pendingPath = url?.path
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let reply = pendingReply, path = pendingPath
        pendingReply = nil; pendingPath = nil
        if success { reply?(path ?? true, nil) } else { reply?(nil, "cancelled") }
    }

    // MARK: alert / confirm / file picker (WKWebView shows none of these by itself)
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = "Zip Receipt"; a.informativeText = message
        a.addButton(withTitle: "OK")
        guard let w = window else { _ = a.runModal(); completionHandler(); return }
        a.beginSheetModal(for: w) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = "Zip Receipt"; a.informativeText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        guard let w = window else { completionHandler(a.runModal() == .alertFirstButtonReturn); return }
        a.beginSheetModal(for: w) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = false
        p.canChooseFiles = true
        guard let w = window else { completionHandler(p.runModal() == .OK ? p.urls : nil); return }
        p.beginSheetModal(for: w) { r in completionHandler(r == .OK ? p.urls : nil) }
    }

    // MARK: keep the app on index.html (a dropped file or a link must not replace it)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL, let index = indexURL, url.standardizedFileURL.path == index.standardizedFileURL.path {
            decisionHandler(.allow); return
        }
        if ["about", "blob", "data"].contains(url.scheme ?? "") { decisionHandler(.allow); return }
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    var window: NSWindow!
    var web: WKWebView!
    let bridge = Bridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "zip")
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 860)
        web = WKWebView(frame: frame, configuration: config)
        web.uiDelegate = bridge
        web.navigationDelegate = bridge

        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Zip Receipt"
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("ZipReceiptMain")
        bridge.web = web
        bridge.window = window

        guard let index = Bundle.main.url(forResource: "index", withExtension: "html") else {
            let a = NSAlert(); a.messageText = "index.html is missing from the app. Run ./build.sh again."; _ = a.runModal()
            NSApp.terminate(nil); return
        }
        bridge.indexURL = index
        web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Give the page a moment to write any unsaved change before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let web = web else { return .terminateNow }
        web.evaluateJavaScript("window.flushSave && window.flushSave(); true") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    @objc func openFolder(_ sender: Any?) {
        try? FileManager.default.createDirectory(at: bridge.base, withIntermediateDirectories: true)
        NSWorkspace.shared.open(bridge.base)
    }

    @objc func reloadPage(_ sender: Any?) { web.reload() }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Zip Receipt", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Zip Receipt", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Zip Receipt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let open = NSMenuItem(title: "Open Zip_Receipt Folder", action: #selector(openFolder(_:)), keyEquivalent: "o")
        open.target = self; fileMenu.addItem(open)
        let reload = NSMenuItem(title: "Reload", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        reload.target = self; fileMenu.addItem(reload)
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win

        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}

