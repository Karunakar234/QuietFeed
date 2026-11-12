import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let model: WebModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView.scrollView.refreshControl?.tintColor = UIColor(Theme.color.accent)
        return model.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
