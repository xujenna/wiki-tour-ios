import SwiftUI
import FirebaseCore

@main
struct WikiTourApp: App {
    init() {
        BundledFonts.register()
        // Navigation bar titles are UIKit, outside SwiftUI's font environment.
        if let title = UIFont(name: BundledFonts.textBold, size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: title]
        }
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
