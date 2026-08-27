import SwiftUI
import WebKit

struct MathWebView: NSViewRepresentable {
    var text: String
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MathWebView
        var isLoaded = false
        
        init(_ parent: MathWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendTextToWebView(webView: webView, text: parent.text)
        }
        
        func sendTextToWebView(webView: WKWebView, text: String) {
            guard isLoaded else { return }
            
            let base64Text = text.data(using: .utf8)?.base64EncodedString() ?? ""
            webView.evaluateJavaScript("updateContent('\(base64Text)')", completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <style>
                :root { color-scheme: light dark; }
                body {
                    font-family: -apple-system, "SF Pro KR", sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                    padding: 5px;
                    margin: 0;
                    word-wrap: break-word;
                    color: WindowText;
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                async function updateContent(base64Str) {
                    const res = await fetch('data:text/plain;base64,' + base64Str);
                    const rawText = await res.text();
                    document.getElementById('content').innerHTML = marked.parse(rawText);
                    renderMathInElement(document.getElementById('content'), {
                        delimiters: [
                            {left: '$$', right: '$$', display: true},
                            {left: '$', right: '$', display: false}
                        ],
                        throwOnError: false
                    });
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sendTextToWebView(webView: webView, text: text)
    }
}
