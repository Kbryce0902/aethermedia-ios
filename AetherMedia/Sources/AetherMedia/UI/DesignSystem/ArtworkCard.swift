import SwiftUI

/// Card presentation mode
public enum ArtworkCardMode {
    case poster     // 2:3 aspect ratio (Grid, Watchlist)
    case backdrop   // 16:9 aspect ratio (Continue Watching, Carousel)
    case compactRow // Horizontal list item
}

/// Touchscreen-optimized artwork card with glass badges, smooth scaling, and VoiceOver support
public struct ArtworkCard: View {
    public let item: MediaItem
    public let mode: ArtworkCardMode
    public var progress: Double? // 0.0 ... 1.0 for continue watching
    public var subtitle: String?
    public var onSelect: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    public init(
        item: MediaItem,
        mode: ArtworkCardMode = .poster,
        progress: Double? = nil,
        subtitle: String? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.item = item
        self.mode = mode
        self.progress = progress
        self.subtitle = subtitle
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            contentView
                .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view media details")
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .poster:
            posterLayout
        case .backdrop:
            backdropLayout
        case .compactRow:
            compactRowLayout
        }
    }
    
    // MARK: - Poster (2:3)
    
    private var posterLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                imageContainer(url: item.posterURL, aspectRatio: 2.0/3.0)
                
                // Rating badge
                if let rating = item.rating, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(item.formattedRating)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .liquidGlass(style: .badge, cornerRadius: 8)
                    .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundColor(.primary)
            
            HStack(spacing: 4) {
                Text(item.type.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let year = item.releaseYear {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(year)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 130)
    }
    
    // MARK: - Backdrop (16:9)
    
    private var backdropLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                imageContainer(url: item.backdropURL ?? item.posterURL, aspectRatio: 16.0/9.0)
                
                // Gradient vignette
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Text overlay
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(10)
                
                // Progress bar for Continue Watching
                if let progress = progress, progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 3)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(width: 240)
    }
    
    // MARK: - Compact Row
    
    private var compactRowLayout: some View {
        HStack(spacing: 12) {
            imageContainer(url: item.posterURL, aspectRatio: 2.0/3.0)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                
                if let sub = subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text(item.overview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if let rating = item.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                    }
                    if let year = item.releaseYear {
                        Text("\(year)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .liquidGlass(style: .card, cornerRadius: 14)
    }
    
    // MARK: - Image Container
    
    private func imageContainer(url: URL?, aspectRatio: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView().scaleEffect(0.8)
                        case .success(let image): image.resizable().scaledToFill()
                        default: fallbackIcon
                        }
                    }
                } else { fallbackIcon }
            }
            .clipped()
    }

    private var fallbackIcon: some View {
        VStack(spacing: 4) {
            Image(systemName: item.type.iconName)
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    private var accessibilityDescription: String {
        var desc = "\(item.title), \(item.type.rawValue)"
        if let year = item.releaseYear { desc += ", released \(year)" }
        if let rating = item.rating { desc += ", rating \(String(format: "%.1f", rating)) out of 10" }
        return desc
    }
}
