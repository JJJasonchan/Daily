import AppKit
import DailyCore
import SwiftUI
import WebKit

// MARK: - 资源

enum MemoLivePreviewResources {
    static let scriptName = "memo-live-preview"

    enum LoadError: LocalizedError {
        case missingScript

        var errorDescription: String? {
            switch self {
            case .missingScript:
                "找不到 memo-live-preview.js。请用 scripts/build-app.sh 构建，或先把组件产物放到 Sources/DailyApp/Resources/Web/。"
            }
        }
    }

    /// 组件产物在 .app 的 Resources/Web/ 下，由 scripts/build-app.sh 拷入。
    static func script() throws -> String {
        let url = Bundle.main.url(
            forResource: scriptName,
            withExtension: "js",
            subdirectory: "Web"
        ) ?? Bundle.main.url(forResource: scriptName, withExtension: "js")

        guard let url else { throw LoadError.missingScript }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - 页面

enum MemoLivePreviewPage {
    /// 组件的 KaTeX 走 MathML 输出，不需要字体和样式表，单个脚本即全部依赖。
    static func html(script: String, initialText: String) -> String {
        let payload = jsonString(initialText)
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <style>
        :root {
          color-scheme: light dark;
          --memo-paper: transparent;
          --memo-ground: transparent;
          --memo-ink: CanvasText;
          --memo-muted: color-mix(in srgb, CanvasText 62%, Canvas);
          --memo-line: color-mix(in srgb, CanvasText 16%, Canvas);
          --memo-accent: #4A6EFA;
          --memo-accent-soft: color-mix(in srgb, var(--memo-accent) 14%, Canvas);
          --memo-highlight: #ffe09a;
          --memo-highlight-ink: #342600;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --memo-accent: #94ADFF;
            --memo-highlight: #624917;
            --memo-highlight-ink: #fff2c3;
          }
        }
        html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
        body {
          font: 14px/1.5 -apple-system, system-ui, sans-serif;
          -webkit-font-smoothing: antialiased;
          overflow: hidden;
          color: var(--memo-ink);
        }
        #editor { height: 100%; }
        .memo-live-preview { height: 100%; background: transparent; }
        .memo-live-preview .cm-editor { height: 100%; background: transparent; }
        .memo-live-preview .cm-scroller {
          overflow-y: auto;
          padding: 14px 18px 40px;
          font-size: 14px;
          line-height: 1.68;
        }
        .memo-live-preview .cm-content { padding-bottom: 24px; }
        .memo-live-preview .cm-line { padding-block: 2px; }
        .memo-live-preview .lp-h1 { font-size: 1.55em; }
        .memo-live-preview .lp-h2 { font-size: 1.3em; }
        .memo-live-preview .lp-h3 { font-size: 1.15em; }
        .memo-live-preview .lp-table td,
        .memo-live-preview .lp-table th { min-width: 72px; padding: 6px 9px; }
        .memo-live-preview ::selection { background: var(--memo-accent-soft); }
        </style>
        </head>
        <body>
        <div id="editor"></div>
        <script>\(script)</script>
        <script>
        (function () {
          var applyingExternal = false;
          function post(message) {
            try { window.webkit.messageHandlers.memo.postMessage(message); } catch (e) {}
          }
          var host = document.getElementById('editor');
          var memo = null;
          try {
            memo = window.MemoLivePreview.createMemoEditor(host, {
              doc: \(payload),
              onChange: function (text) {
                if (applyingExternal) { return; }
                post({ type: 'change', text: text });
              }
            });
          } catch (error) {
            post({ type: 'error', message: String(error && error.message || error) });
            return;
          }

          window.__memoSetDoc = function (text) {
            applyingExternal = true;
            try { memo.setDoc(text); } finally { applyingExternal = false; }
          };
          window.__memoSetTheme = function (accent) {
            if (accent) { document.documentElement.style.setProperty('--memo-accent', accent); }
          };
          window.__memoFocus = function () { try { memo.view.focus(); } catch (e) {} };
          post({ type: 'ready' });
        })();
        </script>
        </body>
        </html>
        """
    }

    /// 把字符串编码成可安全嵌进 <script> 的 JS 字面量。
    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        let encoded = String(decoding: data, as: UTF8.self)
        // </script> 会提前闭合内联脚本。
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }
}

// MARK: - SwiftUI 包装

struct MemoLivePreviewWebView: NSViewRepresentable {
    var text: String
    var onChange: (String) -> Void
    var onReady: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onReady: onReady)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "memo")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        context.coordinator.webView = webView

        do {
            let script = try MemoLivePreviewResources.script()
            webView.loadHTMLString(
                MemoLivePreviewPage.html(script: script, initialText: text),
                baseURL: nil
            )
        } catch {
            context.coordinator.report(error)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onReady = onReady
        context.coordinator.applyTheme(colorScheme, to: webView)
        context.coordinator.applyIfNeeded(text, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "memo")
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onChange: (String) -> Void
        var onReady: (() -> Void)?
        weak var webView: WKWebView?

        private var isReady = false
        private var lastKnownText: String
        private var pendingText: String?
        private var appliedScheme: ColorScheme?

        init(onChange: @escaping (String) -> Void, onReady: (() -> Void)?) {
            self.onChange = onChange
            self.onReady = onReady
            self.lastKnownText = ""
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                if let pendingText, let webView {
                    lastKnownText = pendingText
                    webView.evaluateJavaScript(
                        "window.__memoSetDoc(\(jsLiteral(pendingText)))"
                    )
                    self.pendingText = nil
                }
                onReady?()
            case "change":
                guard let text = payload["text"] as? String else { return }
                lastKnownText = text
                onChange(text)
            case "error":
                let message = payload["message"] as? String ?? "未知错误"
                report(NSError(
                    domain: "MemoLivePreview",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "实时预览初始化失败：\(message)"]
                ))
            default:
                break
            }
        }

        /// 外部内容变化时推给 WebView；用户自己输入的变化不回流。
        func applyIfNeeded(_ text: String, to webView: WKWebView) {
            guard text != lastKnownText else { return }
            guard isReady else {
                pendingText = text
                return
            }
            lastKnownText = text
            webView.evaluateJavaScript("window.__memoSetDoc(\(jsLiteral(text)))")
        }

        func applyTheme(_ scheme: ColorScheme, to webView: WKWebView) {
            guard appliedScheme != scheme else { return }
            appliedScheme = scheme
            let accent = scheme == .dark ? "#94ADFF" : "#4A6EFA"
            webView.evaluateJavaScript("window.__memoSetTheme && window.__memoSetTheme('\(accent)')")
        }

        func report(_ error: Error) {
            lastKnownText = ""
            onReady?()
            NSLog("[MemoLivePreview] %@", error.localizedDescription)
        }

        private func jsLiteral(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
            let encoded = String(decoding: data, as: UTF8.self)
            return encoded.replacingOccurrences(of: "</", with: "<\\/")
        }

        // 组件里 ⌘ 点击链接会尝试导航，拦下来交给系统浏览器。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if url.scheme == "about" || navigationAction.navigationType == .other {
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}
