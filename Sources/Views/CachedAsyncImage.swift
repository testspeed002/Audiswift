import SwiftUI
import AppKit

// MARK: - In-memory image cache

private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: NSImage, for url: URL) {
        let bytes = image.tiffRepresentation?.count ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: bytes)
    }
}

// MARK: - Artwork loader (mirror-aware)

@MainActor
final class ArtworkLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false

    private var currentKey: String?
    private var task: Task<Void, Never>?

    func load(artwork: Artwork?, size: ArtworkSize) {
        let primaryURL = artwork?.url(size: size)
        guard primaryURL != currentKey else { return }
        currentKey = primaryURL

        task?.cancel()
        image = nil

        // Build URL list: primary then mirrors
        var urls: [URL] = []
        if let primary = primaryURL, let url = URL(string: primary) {
            urls.append(url)
        }
        urls += artwork?.mirrorUrls(for: size).compactMap { URL(string: $0) } ?? []

        guard !urls.isEmpty else { return }

        isLoading = true
        task = Task {
            // Check cache first — defer assignment to avoid publishing during view update
            if let cached = ImageCache.shared.image(for: urls[0]) {
                self.image = cached
                self.isLoading = false
                return
            }

            for url in urls {
                guard !Task.isCancelled else { break }
                if let cached = ImageCache.shared.image(for: url) {
                    self.image = cached
                    self.isLoading = false
                    return
                }
                if let loaded = await Self.fetch(url: url) {
                    ImageCache.shared.store(loaded, for: urls[0])
                    self.image = loaded
                    self.isLoading = false
                    return
                }
            }
            self.isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static let maxImageSize = 10 * 1024 * 1024 // 10 MB
    private static let allowedContentTypes = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"]

    private static func fetch(url: URL) async -> NSImage? {
        // Only allow HTTPS downloads
        guard url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            // Validate Content-Type
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                let mimeType = contentType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
                guard allowedContentTypes.contains(mimeType) else { return nil }
            }
            // Enforce size limit
            guard data.count <= maxImageSize else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - SwiftUI view

/// Drop-in replacement for AsyncImage that caches results and falls back to Audius mirror URLs on failure.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let artwork: Artwork?
    let size: ArtworkSize
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @StateObject private var loader = ArtworkLoader()

    init(
        artwork: Artwork?,
        size: ArtworkSize = .medium,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.artwork = artwork
        self.size = size
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let nsImage = loader.image {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
            }
        }
        .task(id: artwork?.url(size: size)) {
            loader.load(artwork: artwork, size: size)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
