import SwiftUI
import FirebaseCore

@main
struct WikiTourApp: App {
    init() {
        BundledFonts.register()
        if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
