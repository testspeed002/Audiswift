import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var themeManager: ThemeManager

    /// When the window drops below this width, the entire UI collapses to a
    /// dedicated mini-player layout — sidebar and main content disappear and
    /// only the now-playing card is shown. Resize the window wider to come
    /// back to the full layout. The 480×480 hard floor on the window itself
    /// (enforced in AppDelegate via contentMinSize + windowWillResize) keeps
    /// this mini layout from shrinking past a usable size.
    private static let miniPlayerThreshold: CGFloat = 860

    var body: some View {
        // GeometryReader as the outer container measures the actual proposed
        // window size and forces children to fit it. NavigationSplitView has
        // its own intrinsic min-width and will refuse to shrink below it
        // when measured via `.background(GeometryReader)`, so the threshold
        // check needs the geometry on the OUTSIDE — this way we know we're
        // in mini mode before NavigationSplitView ever gets to render.
        GeometryReader { proxy in
            Group {
                if proxy.size.width < Self.miniPlayerThreshold {
                    MiniPlayerWindowView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    fullLayout
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: proxy.size.width < Self.miniPlayerThreshold)
        }
        .accentColor(themeManager.currentTheme.accentColor)
        .background(themeManager.currentTheme.backgroundColor)
        .preferredColorScheme(.dark)
    }

    private var fullLayout: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBarView()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
                .background(playerBarChrome)
        }
        .toolbarBackground(viewModel.selectedTab == .nowPlaying ? .hidden : .visible, for: .windowToolbar)
        .overlay(alignment: .top) {
            if let message = playerManager.lastErrorMessage {
                ErrorToast(message: message) {
                    playerManager.lastErrorMessage = nil
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playerManager.lastErrorMessage)
        // Cmd+F → focus whichever search bar is visible. A hidden button
        // is the standard SwiftUI pattern for global shortcuts.
        .background(
            Button("") {
                NotificationCenter.default.post(name: Notification.Name("com.audiswift.focusSearch"), object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    /// Full-width frosted backdrop for the bottom player-bar row. It lives at
    /// the window level so the chrome spans the whole window even though
    /// `PlayerBarView` itself is capped at maxWidth 1100 — no bare "dead
    /// spots" flanking the controls on wide windows. Mirrors the LMA pattern.
    private var playerBarChrome: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            themeManager.currentTheme.accentColor.opacity(0.06),
                            themeManager.currentTheme.panelColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// MARK: - Mini-player window
//
// Shown in place of the full sidebar+detail+player-bar layout when the
// window width drops below `miniPlayerThreshold`. Big artwork, song info,
// scrubber, and transport controls. Resize the window wider to come back to the
// full layout automatically.
struct MiniPlayerWindowView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var fft = FFTAnalyzer.shared

    /// Average of the lowest ~10 FFT bins, shaped with pow(1.6) so the
    /// pulse feels punchier on hits and falls off faster between them.
    private var bassLevel: CGFloat {
        let n = min(10, fft.amplitudes.count)
        guard n > 0 else { return 0 }
        let sum = fft.amplitudes.prefix(n).reduce(0, +)
        let avg = min(1, sum / CGFloat(n))
        return pow(avg, 1.6)
    }

    var body: some View {
        ZStack {
            themeManager.currentTheme.backgroundColor.ignoresSafeArea()

            // Soft artwork bloom behind the foreground content.
            if let currentTrack = playerManager.currentTrack {
                CachedAsyncImage(artwork: currentTrack.artwork, size: .large) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60)
                        .opacity(0.30 + bassLevel * 0.20)
                        .ignoresSafeArea()
                } placeholder: {
                    Color.clear
                }
            }

            // Dim accent-colored pulse
            Circle()
                .fill(themeManager.currentTheme.accentColor)
                .blur(radius: 80)
                .opacity(0.10 + bassLevel * 0.30)
                .scaleEffect(0.85 + bassLevel * 0.25)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.05), value: bassLevel)

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let artSize = max(90, min(220, min(w - 48, h - 200)))
                VStack(spacing: 14) {
                    Spacer(minLength: 36)
                    artworkTile(size: artSize)
                    trackInfo
                    scrubberRow
                    transportRow
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func artworkTile(size: CGFloat) -> some View {
        Group {
            if let currentTrack = playerManager.currentTrack {
                CachedAsyncImage(artwork: currentTrack.artwork, size: .large) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(themeManager.currentTheme.panelColor)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: size * 0.3))
                                .foregroundColor(.secondary)
                        )
                }
            } else {
                Rectangle()
                    .fill(themeManager.currentTheme.panelColor)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(playerManager.currentTrack?.title ?? "Nothing playing")
                .font(.title3).fontWeight(.semibold)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            if let artist = playerManager.currentTrack?.user?.name {
                Text(artist)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scrubberRow: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { playerManager.currentTime },
                    set: { playerManager.seek(to: $0) }
                ),
                in: 0...max(playerManager.duration, 0.001)
            )
            .tint(themeManager.currentTheme.accentColor)
            .accentColor(themeManager.currentTheme.accentColor)
            .disabled(playerManager.currentTrack == nil)

            HStack {
                Text(formatTime(playerManager.currentTime))
                Spacer()
                Text(formatTime(playerManager.duration))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
    }

    private var transportRow: some View {
        HStack(spacing: 4) {
            Button { playerManager.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundColor(playerManager.shuffleEnabled ? themeManager.currentTheme.accentColor : .secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { playerManager.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { playerManager.togglePlayPause() } label: {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button { playerManager.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { playerManager.cycleRepeat() } label: {
                Image(systemName: playerManager.repeatMode.icon)
                    .font(.system(size: 13))
                    .foregroundColor(playerManager.repeatMode == .off ? .secondary : themeManager.currentTheme.accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.primary)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            onDismiss()
        }
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
                
                // Visualizer with active indicator
                Label {
                    HStack {
                        Text("Visualizer")
                        Spacer()
                        if playerManager.currentTrack != nil {
                            Circle()
                                .fill(themeManager.currentTheme.accentColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                } icon: {
                    Image(systemName: "waveform.circle.fill")
                }
                .tag(LibraryViewModel.Tab.nowPlaying)
            }
            Section("Discover") {
                SidebarRow(icon: "chart.line.uptrend.xyaxis", title: "Trending", tab: .trending)
            }
            Section("Settings") {
                Button {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.showPreferences()
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
            // User profile lives inside the List so it scrolls with the
            // sidebar content. Previously this was in a sidebar
            // .safeAreaInset(edge: .bottom), which collided with the outer
            // NavigationSplitView's player-bar safe-area inset when the
            // window was short — the player bar visually covered the chip.
            if auth.isSignedIn, let user = auth.currentUser {
                Section {
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

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
        .navigationTitle("Audiswift")
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
            .id(viewModel.selectedTab)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity.combined(with: .offset(x: -16))
            ))
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: viewModel.selectedTab)
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
        case .nowPlaying: return "Visualizer"
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ZStack {
            // Background ambient visualizer
            AtmosphericVisualizer()
                .opacity(0.4)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greetingText)
                            .font(.system(size: 34, weight: .bold))
                        Text("Welcome back to Audiswift.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)

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

                    // Hero Card — #1 trending track on Audius
                    if let hero = viewModel.trendingTracks.first {
                        heroCard(track: hero, context: viewModel.trendingTracks)
                            .padding(.horizontal)
                    }

                    // Featured row
                    let featured = viewModel.featuredTracks
                    if !featured.isEmpty {
                        sectionHeader("Featured")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(featured.prefix(6)) { track in
                                    TrackCard(track: track, cardSize: 180)
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
                    }

                    // Recently Played
                    RecentlyPlayedSection()
                }
                .padding(.bottom, 140)
            }
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

    /// Apple-Music–style hero: tall artwork, palette-rendered "Trending"
    /// chip, large rounded title, and a prominent Play / Shuffle action row.
    /// All controls follow HIG capsule patterns; Shuffle is glass material so
    /// Play is unambiguously the primary action (HIG: Primary Action).
    @ViewBuilder
    private func heroCard(track: Track, context: [Track] = []) -> some View {
        let playContext = context.isEmpty ? [track] : context
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(artwork: track.artwork, size: .large) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(themeManager.currentTheme.cardColor)
            }
            .frame(height: 280)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.25), .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Label("Trending #1", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(themeManager.currentTheme.accentColor, .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))

                Text(track.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                if let user = track.user {
                    Text(user.name)
                        .font(.title3.weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Button {
                        playerManager.play(track: track, context: playContext)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 22)
                            .background(themeManager.currentTheme.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Play this track")

                    Button {
                        let shuffled = playContext.shuffled()
                        if let first = shuffled.first {
                            playerManager.play(track: first, context: shuffled)
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.body.weight(.semibold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 22)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Shuffle the trending list")
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
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
    @EnvironmentObject var themeManager: ThemeManager
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var bioExpanded = false

    /// Apple HIG: keep typography hierarchical and let the artwork dominate.
    /// Hero height scales nicely with the resizable window. 320 pt feels
    /// "Apple Music"-sized without crowding the tracks below.
    private let heroHeight: CGFloat = 320

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionRow
                bioBlock
                contentSections
                Spacer(minLength: 160)
            }
        }
        .background(themeManager.currentTheme.backgroundColor)
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

    // MARK: Hero

    /// Apple Music–style hero: a blurred copy of the avatar fills the
    /// background, dimmed by a gradient so the foreground name/handle
    /// remain legible against any color (HIG: Materials & Color Contrast).
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred backdrop. Falls through to a flat accent panel if
            // there's no artwork.
            CachedAsyncImage(artwork: user.profilePicture, size: .large) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 50)
                    .opacity(0.55)
                    .clipped()
            } placeholder: {
                themeManager.currentTheme.accentColor.opacity(0.25)
            }
            .frame(height: heroHeight)
            .clipped()

            // Bottom-fading scrim — keeps title text high-contrast over any backdrop.
            LinearGradient(
                colors: [Color.black.opacity(0.0),
                         Color.black.opacity(0.35),
                         themeManager.currentTheme.backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)

            // Foreground content
            HStack(alignment: .bottom, spacing: 20) {
                CachedAsyncImage(artwork: user.profilePicture, size: .medium) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                }
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(user.name)
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if user.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, themeManager.currentTheme.accentColor)
                                .font(.title2)
                                .accessibilityLabel("Verified artist")
                        }
                    }
                    Text("@\(user.handle)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    if user.allowAiAttribution == true {
                        Label("Allows AI Attribution", systemImage: "sparkles")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
    }

    // MARK: Actions + Stats

    /// Apple Music–style action row: prominent Play / Shuffle, with stats on
    /// the right. App Store §4.5.2 — standard media controls (play, skip)
    /// must always be reachable; this row mirrors that pattern at the
    /// browse-page level.
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first {
                    playerManager.play(track: first, context: tracks)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(themeManager.currentTheme.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.4 : 1)
            .help("Play all tracks")

            Button {
                guard !tracks.isEmpty else { return }
                let shuffled = tracks.shuffled()
                if let first = shuffled.first {
                    playerManager.play(track: first, context: shuffled)
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.4 : 1)
            .help("Shuffle all tracks")

            Spacer()

            HStack(spacing: 24) {
                if let followers = user.followerCount {
                    statView(count: followers, label: "Followers")
                }
                if let trackCount = user.trackCount {
                    statView(count: trackCount, label: "Tracks")
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Bio

    @ViewBuilder
    private var bioBlock: some View {
        if let bio = user.bio, !bio.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(bio)
                    .font(.body)
                    .lineSpacing(2)
                    .lineLimit(bioExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.primary.opacity(0.85))
                if bio.count > 140 {
                    Button(bioExpanded ? "Show less" : "Show more") {
                        withAnimation(.easeInOut(duration: 0.2)) { bioExpanded.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Tracks + Playlists

    @ViewBuilder
    private var contentSections: some View {
        if isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
        } else {
            if !tracks.isEmpty {
                sectionHeader("Tracks")
                LazyVStack(spacing: 4) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                        TrackRowView(track: track, index: i + 1, context: tracks)
                    }
                }
                .padding(.horizontal, 16)
            }

            if !playlists.isEmpty {
                sectionHeader("Playlists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(playlists) { playlist in
                            NavigationLink(value: playlist) {
                                VStack(alignment: .leading, spacing: 8) {
                                    CachedAsyncImage(artwork: playlist.artwork, size: .medium) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)

                                    Text(playlist.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                        .frame(width: 160, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            if tracks.isEmpty && playlists.isEmpty {
                Text("No public tracks or playlists.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.bold))
            .padding(.horizontal, 24)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func statView(count: Int, label: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(formatCount(count))
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// HIG: localized number formatting; abbreviate large counts (1.2K, 3.4M)
    /// the way Apple Music does so the stats row fits compact widths.
    private func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: "%.1fM", v)
        } else if n >= 1_000 {
            let v = Double(n) / 1_000
            return String(format: "%.1fK", v)
        }
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - PlaylistDetailView

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    private let heroHeight: CGFloat = 320

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionRow
                contentSection
                Spacer(minLength: 160)
            }
        }
        .background(themeManager.currentTheme.backgroundColor)
        .navigationTitle(playlist.name)
        .task {
            isLoading = true
            tracks = (try? await AudiusAPI.getPlaylistTracks(playlistId: playlist.id)) ?? []
            isLoading = false
        }
    }

    /// Apple-Music–style hero: blurred artwork backdrop, large rounded title,
    /// playlist artwork tile on the leading edge. HIG: Materials + Hierarchy.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(artwork: playlist.artwork, size: .large) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 50)
                    .opacity(0.55)
                    .clipped()
            } placeholder: {
                themeManager.currentTheme.accentColor.opacity(0.25)
            }
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), themeManager.currentTheme.backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)

            HStack(alignment: .bottom, spacing: 20) {
                CachedAsyncImage(artwork: playlist.artwork, size: .medium) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.secondary))
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Playlist", systemImage: "music.note.list")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    Text(playlist.name)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    if let user = playlist.user {
                        NavigationLink(value: user) {
                            Text("By \(user.name)")
                                .font(.title3.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first {
                    playerManager.play(track: first, context: tracks)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(themeManager.currentTheme.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.4 : 1)

            Button {
                guard !tracks.isEmpty else { return }
                let shuffled = tracks.shuffled()
                if let first = shuffled.first {
                    playerManager.play(track: first, context: shuffled)
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.4 : 1)

            Spacer()

            if let count = playlist.trackCount {
                VStack(alignment: .center, spacing: 2) {
                    Text(formatCount(count)).font(.title3.weight(.bold))
                    Text("Tracks").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var contentSection: some View {
        if isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
        } else if tracks.isEmpty {
            Text("No tracks in this playlist.")
                .foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 4) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    TrackRowView(track: track, index: i + 1, context: tracks)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
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
