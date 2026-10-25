import SwiftUI
import UIKit

/// Available bottom tabs
public enum AetherTab: String, CaseIterable {
    case home = "Home"
    case search = "Search"
    case library = "Library"
    case settings = "Settings"
    
    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "square.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Floating glass tab bar styled according to Apple Liquid Glass principles
public struct AetherTabBar: View {
    @Binding public var selectedTab: AetherTab
    
    public init(selectedTab: Binding<AetherTab>) {
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(AetherTab.allCases, id: \.self) { tab in
                Button(action: {
                    #if os(iOS)
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44) // Guaranteed Apple 44pt touch target
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .liquidGlass(style: .navBar, cornerRadius: 32)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
