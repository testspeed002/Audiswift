import SwiftUI
import AppKit

// MARK: - Native text field

struct NativeTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Paste your access token"
        field.stringValue = text
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        init(_ parent: NativeTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }
    }
}

// MARK: - Unified TrackCard (replaces FeaturedTrackCard + GridTrackCard)

struct TrackCard: View {
    let track: Track
    var cardSize: CGFloat = 180
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(artwork: track.artwork, size: .medium) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.secondary))
                }
                .frame(width: cardSize, height: cardSize)
                .cornerRadius(8)
                .overlay(
                    // Dark scrim on hover
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(isHovered ? 0.3 : 0))
                )
                .overlay(
                    // Glass border on hover
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.15 : 0), lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(0.3),
                    radius: isHovered ? 15 : 5,
                    x: 0,
                    y: isHovered ? 8 : 2
                )
                .onTapGesture { playerManager.play(track: track) }

                // AI badge — top-left corner of artwork
                if track.isAiAttributed {
                    VStack {
                        HStack {
                            Text("AI")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(colors: [Color.purple, Color.indigo],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(4)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: cardSize, height: cardSize)
                    .allowsHitTesting(false)
                }

                Image(systemName: playerManager.currentTrack?.id == track.id && playerManager.isPlaying
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .shadow(radius: 4)
                    .opacity(isHovered || (playerManager.currentTrack?.id == track.id && playerManager.isPlaying) ? 1 : 0)
                    .padding(8)
                    .allowsHitTesting(false)
            }

            Text(track.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: cardSize, alignment: .leading)
                .opacity(isHovered ? 1.0 : 0.7)

            if let user = track.user {
                NavigationLink(value: user) {
                    Text(user.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: cardSize, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: cardSize)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - TrendingView

private let genreOptions: [String?] = [nil, "Electronic", "Hip-Hop/Rap", "Pop", "Rock", "R&B/Soul", "Jazz", "Classical", "Latin", "House", "Techno", "Ambient"]
private let genreLabels: [String] = ["All", "Electronic", "Hip-Hop", "Pop", "Rock", "R&B/Soul", "Jazz", "Classical", "Latin", "House", "Techno", "Ambient"]

struct TrendingView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Trending")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Picker("View", selection: $viewModel.viewMode) {
                    Image(systemName: "list.bullet").tag(LibraryViewModel.ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(LibraryViewModel.ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            .padding()

            // Time filter
            HStack {
                Picker("Time", selection: $viewModel.trendingTimeFilter) {
                    Text("This Week").tag("week")
                    Text("This Month").tag("month")
                    Text("All Time").tag("allTime")
                }
                .pickerStyle(.segmented)
                .frame(width: 300) // Keeps it from expanding too much
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onChange(of: viewModel.trendingTimeFilter) { _, _ in
                Task { await viewModel.applyTrendingFilters() }
            }

            // Genre pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<genreOptions.count, id: \.self) { i in
                        let genre = genreOptions[i]
                        let label = genreLabels[i]
                        let selected = viewModel.trendingGenreFilter == genre
                        Button(label) {
                            viewModel.trendingGenreFilter = genre
                            Task { await viewModel.applyTrendingFilters() }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? themeManager.currentTheme.accentColor : Color.secondary.opacity(0.12))
                        .foregroundColor(selected ? .white : .primary)
                        .cornerRadius(16)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            // Content
            if viewModel.isLoading {
                Spacer()
                HStack { Spacer(); ProgressView(); Spacer() }
                Spacer()
            } else if let error = viewModel.error {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error).foregroundColor(.secondary)
                    Button("Retry") { Task { await viewModel.loadTrending() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
            } else if viewModel.viewMode == .list {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(viewModel.trendingTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(track: track, index: index + 1, context: viewModel.trendingTracks)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .refreshable { await viewModel.loadTrending() }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20)], spacing: 20) {
                        ForEach(viewModel.trendingTracks) { track in
                            TrackCard(track: track)
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .refreshable { await viewModel.loadTrending() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.currentTheme.backgroundColor)
        .task {
            if viewModel.trendingTracks.isEmpty { await viewModel.loadTrending() }
        }
    }
}

// MARK: - SearchView

struct SearchView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @State private var searchText: String = ""

    private let defaultGenres = ["Electronic", "Hip-Hop", "Pop", "R&B/Soul", "Rock", "Lofi", "House", "Techno"]
    private let genreColors: [Color] = [.pink, .blue, .purple, .orange, .red, .teal, .green, .indigo]

    var body: some View {
        VStack(spacing: 0) {
            // Glass search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search songs, albums, artists", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in viewModel.search(query: newValue) }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if viewModel.isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.currentTheme.panelColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(themeManager.currentTheme.glassEdgeColor, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            if searchText.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Browse Genres")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach(0..<defaultGenres.count, id: \.self) { i in
                                genreCard(title: defaultGenres[i], color: genreColors[i])
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 100)
                }
            } else if viewModel.isSearching && viewModel.searchResults.isEmpty {
                // Shimmer placeholders for search results
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { _ in
                            ShimmerView()
                                .frame(height: 60)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            } else if viewModel.searchResults.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No results for \"\(searchText)\"")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.searchResults) { track in
                            TrackRowView(track: track, context: viewModel.searchResults)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.currentTheme.backgroundColor)
    }
    
    @ViewBuilder
    private func genreCard(title: String, color: Color) -> some View {
        Button {
            searchText = title
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.8), color.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(8)
                    .offset(x: 10, y: 10)
                    .rotationEffect(.degrees(15))
            }
            .frame(height: 100)
            .clipped()
            .cornerRadius(12)
            .shadow(color: color.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LibraryView (sign-in gate)

struct LibraryView: View {
    @ObservedObject private var auth = AudiusAuth.shared
    @EnvironmentObject var themeManager: ThemeManager
    @State private var manualToken: String = ""
    @State private var showManualEntry: Bool = false

    var body: some View {
        if auth.isSignedIn {
            SignedInLibraryView()
        } else {
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 24) {
                    // Logo/Icon
                    ZStack {
                        Circle()
                            .fill(themeManager.currentTheme.accentColor.opacity(0.15))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 40))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    .shadow(color: themeManager.currentTheme.accentColor.opacity(0.3), radius: 20)
                    
                    // Text
                    VStack(spacing: 8) {
                        Text("Your Library")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Sign in to access your saved tracks, playlists, and history across all your devices.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    
                    // Auth Actions
                    VStack(spacing: 16) {
                        if showManualEntry {
                            VStack(spacing: 12) {
                                HStack {
                                    SecureField("Paste your access token", text: $manualToken)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(height: 32)
                                        .onChange(of: manualToken) { _, newValue in
                                            if newValue.count > 1024 {
                                                manualToken = String(newValue.prefix(1024))
                                            }
                                        }
                                    
                                    Button("Paste") {
                                        if let s = NSPasteboard.general.string(forType: .string) {
                                            manualToken = String(s.prefix(1024))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                Button("Connect Account") {
                                    let trimmed = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty, trimmed.count >= 10 else { return }
                                    auth.setManualToken(trimmed)
                                }
                                .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 ? themeManager.currentTheme.accentColor : themeManager.currentTheme.cardColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .animation(.easeInOut, value: manualToken)
                                
                                Button("Cancel") {
                                    withAnimation { showManualEntry = false }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .buttonStyle(.plain)
                            }
                            .frame(width: 320)
                            .padding(20)
                            .background(themeManager.currentTheme.panelColor)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(themeManager.currentTheme.glassEdgeColor, lineWidth: 1)
                            )
                        } else {
                            Button(action: { auth.signIn() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.up.forward.square.fill")
                                    Text("Sign In With Audius")
                                        .fontWeight(.semibold)
                                }
                                .frame(width: 240)
                                .padding(.vertical, 14)
                                .background(themeManager.currentTheme.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: themeManager.currentTheme.accentColor.opacity(0.3), radius: 10, y: 4)
                            }
                            .buttonStyle(.plain)

                            Button("Enter Token Manually") {
                                withAnimation { showManualEntry = true }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeManager.currentTheme.backgroundColor)
        }
    }
}

// MARK: - SignedInLibraryView

struct SignedInLibraryView: View {
    @ObservedObject private var auth = AudiusAuth.shared
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var playlists: [Playlist] = []
    @State private var likedTracks: [Track] = []
    @State private var isLoading = true
    @State private var likedError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Library").font(.title).fontWeight(.bold)
                Spacer()
                Button("Sign Out") { auth.signOut() }
                    .foregroundColor(.secondary).buttonStyle(.plain)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .padding(.top, 60)
                    } else {
                        // ── Liked Tracks ─────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Liked Tracks", systemImage: "heart.fill")
                                    .font(.title2).fontWeight(.bold)
                                    .foregroundStyle(themeManager.currentTheme.accentColor)
                                Spacer()
                                if !likedTracks.isEmpty {
                                    Button {
                                        playerManager.play(track: likedTracks[0], context: likedTracks)
                                    } label: {
                                        Label("Play All", systemImage: "play.fill")
                                            .font(.caption).fontWeight(.medium)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(themeManager.currentTheme.accentColor)
                                    .controlSize(.small)
                                }
                            }

                            if let error = likedError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text(error).font(.caption).foregroundColor(.secondary)
                                }
                            } else if likedTracks.isEmpty {
                                Text("No liked tracks yet.")
                                    .foregroundColor(.secondary).font(.subheadline)
                            } else {
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(likedTracks.enumerated()), id: \.element.id) { i, track in
                                        TrackRowView(track: track, index: i + 1, context: likedTracks)
                                    }
                                }
                            }
                        }

                        // ── Playlists ─────────────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your Playlists", systemImage: "music.note.list")
                                .font(.title2).fontWeight(.bold)

                            if playlists.isEmpty {
                                VStack(spacing: 8) {
                                    Text("No playlists found")
                                        .font(.subheadline).foregroundColor(.secondary)
                                    Text("Only playlists you've **created** on Audius appear here.")
                                        .font(.caption).foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20)], spacing: 20) {
                                    ForEach(playlists) { playlist in
                                        NavigationLink(value: playlist) {
                                            VStack(alignment: .leading) {
                                                CachedAsyncImage(artwork: playlist.artwork, size: .medium) { image in
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Rectangle().fill(Color.gray.opacity(0.3))
                                                }
                                                .frame(width: 180, height: 180)
                                                .cornerRadius(8)

                                                Text(playlist.name)
                                                    .font(.subheadline).lineLimit(1)
                                                    .foregroundColor(.primary)
                                                if let count = playlist.trackCount {
                                                    Text("\(count) tracks")
                                                        .font(.caption).foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 100)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.backgroundColor)
        .task(id: auth.currentUser?.id) {
            guard let userId = auth.currentUser?.id else { isLoading = false; return }
            isLoading = true
            
            // Fetch both in parallel
            async let fetchedPlaylists = try? AudiusAPI.getUserPlaylists(userId: userId)
            async let fetchedLiked = AudiusAPI.getUserFavorites(userId: userId)

            playlists = await fetchedPlaylists ?? []

            do {
                likedTracks = try await fetchedLiked
            } catch {
                likedError = "Couldn't load liked tracks: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }
}
