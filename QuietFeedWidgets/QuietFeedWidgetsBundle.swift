import SwiftUI
import WidgetKit

@main
struct QuietFeedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
        QuickAppsWidget()
        OpenQuietFeedWidget()
        LibraryWidget()
        LauncherWidget()
        FocusWidget()
        #if os(iOS)
        FocusLiveActivity()
        #endif
    }
}
