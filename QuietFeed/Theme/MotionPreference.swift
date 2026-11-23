import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Kept out of Theme.swift, which is generated from design tokens.
extension Motion {
    /// The app's spring, or no animation when the person has Reduce Motion on, so panels,
    /// the mini-player and tabs change in place instead of sliding and scaling.
    static var gentle: Animation? {
        prefersReducedMotion ? nil : spring
    }

    static var prefersReducedMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }
}
