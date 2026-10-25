import SwiftUI

/// Reusable empty state view with glass styling
public struct EmptyStateCard: View {
    public let icon: String
    public let title: String
    public let message: String
    public var actionTitle: String?
    public var action: (() -> Void)?
    
    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            if let actionTitle = actionTitle, let action = action {
                GlassButton(title: actionTitle, variant: .secondary, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .liquidGlass(style: .card, cornerRadius: 22)
        .padding(.horizontal, 20)
    }
}

/// Readable, shareable error banner. Response field paths must not be truncated.
public struct ErrorStateBanner: View {
    public let message: String
    public let details: String?
    public let retryAction: () -> Void

    public init(message: String, details: String? = nil, retryAction: @escaping () -> Void) {
        self.message = message; self.details = details; self.retryAction = retryAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange).font(.title3)
                Text(message)
                    .font(.footnote).foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button("Retry", action: retryAction)
                    .font(.footnote.bold()).foregroundColor(.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    .fixedSize()
            }
            if let details {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: "AetherMedia \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")\n\(message)\n\(details)") {
                            Label("Share error details", systemImage: "square.and.arrow.up")
                        }.font(.footnote)
                    }.padding(.top, 6)
                }.font(.footnote)
            }
        }
        .padding(12).liquidGlass(style: .badge, cornerRadius: 14)
        .padding(.horizontal, 16)
    }
}
