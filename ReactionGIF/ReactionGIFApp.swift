import SwiftUI

/// The main app entry point. The bulk of the experience also lives in the share
/// extension, but the app itself lets users pick a screenshot from their library
/// and react to it without leaving ReactionGIF.
@main
struct ReactionGIFApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
