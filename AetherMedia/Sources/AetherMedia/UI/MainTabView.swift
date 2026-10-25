import SwiftUI

/// Main container displaying the four primary tabs with the floating glass tab bar
@MainActor
public struct MainTabView: View {
    @State private var selectedTab: AetherTab = .home
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .search:
                    SearchView()
                case .library:
                    LibraryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AetherTabBar(selectedTab: $selectedTab)
        }
    }
}
