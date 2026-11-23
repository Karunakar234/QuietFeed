import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit

struct WebViewContainer: UIViewRepresentable {
    let model: WebModel
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        applyAppearance(to: model.webView)
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

    func updateUIView(_ uiView: WKWebView, context: Context) {
        applyAppearance(to: uiView)
    }

    private func applyAppearance(to webView: WKWebView) {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        guard webView.overrideUserInterfaceStyle != style else { return }

        // Let standards-based sites react through prefers-color-scheme while preserving
        // the existing page, playback session, and scroll position.
        UIView.performWithoutAnimation {
            webView.overrideUserInterfaceStyle = style
        }
    }
}
#elseif canImport(AppKit)
import AppKit

struct WebViewContainer: NSViewRepresentable {
    let model: WebModel
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> WKWebView {
        applyAppearance(to: model.webView)
        return model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        applyAppearance(to: nsView)
    }

    private func applyAppearance(to webView: WKWebView) {
        webView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
    }
}
#endif
