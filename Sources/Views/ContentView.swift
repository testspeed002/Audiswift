import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .safeAreaInset(edge: .bottom) {
            PlayerBarView()
        }
        .accentColor(themeManager.currentTheme.accentColor)
        .background(themeManager.currentTheme.backgroundColor)
        .preferredColorScheme(.dark) // All themes are dark mode
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var auth = AudiusAuth.shared
    @ObservedObject private var playerManager = AudioPlayerManager.shared

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedTab },
            set: { if let tab = $0 { viewModel.selectTab(tab) } }
        )) {
            Section("Library") {
                SidebarRow(icon: "house.fill",          title: "Home",    tab: .home)
                SidebarRow(icon: "magnifyingglass",     title: "Search",  tab: .search)
                SidebarRow(icon: "music.note.list",     title: "Library", tab: .library)
                
                // Now Playing with active indicator
                Label {
                    HStack {
                        Text("Now Playing")
                        Spacer()
                        if playerManager.currentTrack != nil {
                            Circle()
                                .fill(themeManager.currentTheme.accentColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                } icon: {
                    Image(systemName: "play.rectangle.fill")
                }
                .tag(LibraryViewModel.Tab.nowPlaying)
            }
            Section("Discover") {
                SidebarRow(icon: "chart.line.uptrend.xyaxis", title: "Trending", tab: .trending)
            }
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { ThemeManager.shared.currentTheme },
                    set: { ThemeManager.shared.currentTheme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.rawValue, systemImage: themeIcon(for: theme))
                            .tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // User profile section at sidebar bottom
            if auth.isSignedIn, let user = auth.currentUser {
                HStack(spacing: 10) {
                    CachedAsyncImage(artwork: user.profilePicture, size: .small) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(themeManager.currentTheme.accentColor.opacity(0.2))
                            .overlay(Image(systemName: "person.fill").font(.caption).foregroundColor(.secondary))
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text("@\(user.handle)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(themeManager.currentTheme.panelColor.opacity(0.5))
            }
        }
        .navigationTitle("Audiswift")
    }
    
    private func themeIcon(for theme: AppTheme) -> String {
        switch theme {
        case .default: return "paintpalette.fill"
        case .classic: return "sparkles"
        case .matrix:  return "terminal.fill"
        case .sunset:  return "sun.horizon.fill"
        case .ocean:   return "water.waves"
        }
    }
}

struct SidebarRow: View {
    let icon: String; let title: String; let tab: LibraryViewModel.Tab
    @EnvironmentObject var viewModel: LibraryViewModel
    var body: some View { Label(title, systemImage: icon).tag(tab) }
}

// MARK: - Detail (navigation host)

struct DetailView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.selectedTab {
                case .home:     HomeView()
                case .search:   SearchView()
                case .library:  LibraryView()
                case .trending: TrendingView()
                case .nowPlaying: VisualizerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)
            .navigationTitle(tabTitle)
            .navigationDestination(for: User.self)     { user     in UserProfileView(user: user) }
            .navigationDestination(for: Playlist.self) { playlist in PlaylistDetailView(playlist: playlist) }
            .navigationDestination(for: Track.self)    { track    in TrackDetailView(track: track) }
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            navigationPath.removeLast(navigationPath.count)
        }
    }

    private var tabTitle: String {
        switch viewModel.selectedTab {
        case .home:     return "Audiswift"
        case .search:   return "Search"
        case .library:  return "Library"
        case .trending: return "Trending"
        case .nowPlaying: return "Now Playing"
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(greetingText)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                // Error + retry
                if let error = viewModel.error {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                        Text(error).foregroundColor(.secondary).font(.subheadline)
                        Spacer()
                        Button("Retry") { Task { await viewModel.loadTrending() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Hero Card — first featured track
                let featured = viewModel.featuredTracks
                if let hero = featured.first {
                    heroCard(track: hero)
                        .padding(.horizontal)
                }

                // Featured row (skip first since it's the hero)
                if featured.count > 1 {
                    sectionHeader("Featured")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(featured.dropFirst().prefix(5)) { track in
                                TrackCard(track: track, cardSize: 180)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else if viewModel.isLoading {
                    // Shimmer placeholder
                    sectionHeader("Featured")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<4, id: \.self) { _ in
                                ShimmerView()
                                    .frame(width: 180, height: 220)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Top Tracks (weekly)
                if !viewModel.trendingTracks.isEmpty {
                    sectionHeader("Top Tracks This Week")
                    LazyVStack(spacing: 4) {
                        ForEach(Array(viewModel.trendingTracks.prefix(10).enumerated()), id: \.element.id) { i, track in
                            TrackRowView(track: track, index: i + 1, context: Array(viewModel.trendingTracks.prefix(10)))
                        }
                    }
                    .padding(.horizontal)
                } else if viewModel.isLoading {
                    sectionHeader("Top Tracks This Week")
                    VStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            ShimmerView()
                                .frame(height: 60)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }

                // Recently Played
                RecentlyPlayedSection()
            }
            .padding(.top)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.currentTheme.backgroundColor)
        .refreshable {
            await viewModel.loadTrending()
            await viewModel.loadFeatured()
        }
        .task {
            async let trending: () = viewModel.trendingTracks.isEmpty ? viewModel.loadTrending() : ()
            async let featured: () = viewModel.featuredTracks.isEmpty ? viewModel.loadFeatured() : ()
            _ = await (trending, featured)
        }
    }

    // MARK: - Hero Card
    
    @ViewBuilder
    private func heroCard(track: Track) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(artwork: track.artwork, size: .large) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(themeManager.currentTheme.cardColor)
            }
            .frame(height: 240)
            .clipped()
            .cornerRadius(16)
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .cornerRadius(16)
            
            // Track info
            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .tracking(1.5)
                
                Text(track.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let user = track.user {
                    Text(user.name)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Button {
                    playerManager.play(track: track)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Play Now")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2).fontWeight(.bold)
            .padding(.horizontal)
    }
}

// MARK: - Shimmer Loading Placeholder

struct ShimmerView: View {
    @State private var phase: CGFloat = -1
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.6)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - UserProfileView

struct UserProfileView: View {
    let user: User
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ── Header ──────────────────────────────────────────────
                HStack(alignment: .top, spacing: 20) {
                    CachedAsyncImage(artwork: user.profilePicture, size: .medium) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .shadow(radius: 6)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(user.name).font(.largeTitle).fontWeight(.bold)
                            if user.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.pink).font(.title2)
                            }
                            if user.allowAiAttribution == true {
                                Text("AI Attribution")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        LinearGradient(colors: [Color.purple, Color.indigo],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .cornerRadius(10)
                            }
                        }
                        Text("@\(user.handle)").font(.title3).foregroundColor(.secondary)

                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio).font(.body).padding(.top, 4)
                                .lineLimit(4)
                        }

                        HStack(spacing: 20) {
                            if let followers = user.followerCount {
                                statView(count: followers, label: "Followers")
                            }
                            if let trackCount = user.trackCount {
                                statView(count: trackCount, label: "Tracks")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else {
                    // ── Tracks ───────────────────────────────────────
                    if !tracks.isEmpty {
                        HStack {
                            sectionHeader("Tracks")
                            Spacer()
                            if !tracks.isEmpty {
                                Button {
                                    playerManager.play(track: tracks[0], context: tracks)
                                } label: {
                                    Label("Play All", systemImage: "play.fill")
                                        .font(.caption).fontWeight(.medium)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.pink)
                                .controlSize(.small)
                                .padding(.horizontal)
                            }
                        }
                        
                        LazyVStack(spacing: 4) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                                TrackRowView(track: track, index: i + 1, context: tracks)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ── Playlists ─────────────────────────────────────────
                    if !playlists.isEmpty {
                        sectionHeader("Playlists")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(playlists) { playlist in
                                    NavigationLink(value: playlist) {
                                        VStack(alignment: .leading) {
                                            CachedAsyncImage(artwork: playlist.artwork, size: .medium) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 160, height: 160)
                                            .cornerRadius(8)

                                            Text(playlist.name)
                                                .font(.subheadline).lineLimit(1)
                                                .foregroundColor(.primary)
                                                .frame(width: 160, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if tracks.isEmpty && playlists.isEmpty {
                        Text("No public tracks or playlists.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }

                Spacer(minLength: 100)
            }
        }
        .navigationTitle(user.name)
        .task {
            isLoading = true
            async let fetchedTracks    = try? AudiusAPI.getUserTracks(userId: user.id)
            async let fetchedPlaylists = try? AudiusAPI.getUserPlaylists(userId: user.id)
            tracks    = await fetchedTracks    ?? []
            playlists = await fetchedPlaylists ?? []
            isLoading = false
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.title2).fontWeight(.bold).padding(.horizontal)
    }

    @ViewBuilder
    private func statView(count: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)").fontWeight(.semibold)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - PlaylistDetailView

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    CachedAsyncImage(artwork: playlist.artwork, size: .large) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.secondary))
                    }
                    .frame(width: 160, height: 160)
                    .cornerRadius(10)
                    .shadow(radius: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(playlist.name).font(.largeTitle).fontWeight(.bold)
                        if let user = playlist.user {
                            NavigationLink(value: user) {
                                Text("By \(user.name)").font(.subheadline).foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        if let count = playlist.trackCount {
                            Text("\(count) tracks").font(.caption).foregroundColor(.secondary)
                        }
                        if !tracks.isEmpty {
                            Button {
                                playerManager.play(track: tracks[0], context: tracks)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.pink)
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else if tracks.isEmpty {
                    Text("No tracks in this playlist.")
                        .foregroundColor(.secondary).frame(maxWidth: .infinity).padding()
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                            TrackRowView(track: track, index: i + 1, context: tracks)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 100)
            }
        }
        .navigationTitle(playlist.name)
        .task {
            isLoading = true
            tracks = (try? await AudiusAPI.getPlaylistTracks(playlistId: playlist.id)) ?? []
            isLoading = false
        }
    }
}

// MARK: - Recently Played Section

struct RecentlyPlayedSection: View {
    @ObservedObject private var history = PlaybackHistory.shared
    @EnvironmentObject var playerManager: AudioPlayerManager

    var body: some View {
        if !history.recentlyPlayed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("Recently Played")
                    Spacer()
                    Button("Clear") {
                        history.clear()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(history.recentlyPlayed.prefix(10)) { track in
                            TrackCard(track: track, cardSize: 160)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.horizontal)
    }
}
