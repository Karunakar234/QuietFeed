import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit

struct WebViewContainer: UIViewRepresentable {
    let model: WebModel

    func makeUIView(context: Context) -> WKWebView {
        let scrollView = model.webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.scrollsToTop = true
        scrollView.refreshControl?.tintColor = UIColor(Theme.color.accent)
        return model.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit

struct WebViewContainer: NSViewRepresentable {
    let model: WebModel

    func makeNSView(context: Context) -> WKWebView {
        return model.webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
