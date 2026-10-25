import SwiftUI

@main
@MainActor
public struct AetherMediaApp: App {
    public init() {
        // Apply global appearance defaults
    }
    
    public var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.environment["AETHERMEDIA_UNIT_TESTING"] == "1" {
                    Color.clear
                } else { MainTabView() }
            }
                .preferredColorScheme(.dark) // Kodi replacement defaults to sleek dark glass aesthetic
        }
    }
}
