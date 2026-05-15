import SwiftUI

struct TrackDetailView: View {
    let track: Track
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let heroHeight: CGFloat = 360

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionRow
                metadataRow
                descriptionSection
                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.currentTheme.backgroundColor)
        .navigationTitle("Track Details")
        .overlay(alignment: .topTrailing) {
            Button {
                if let onClose = onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(20)
            .help("Press ESC or click to close")
        }
    }

    // MARK: Hero

    /// Apple-Music–style track hero: blurred artwork backdrop, large 240 pt
    /// artwork tile on the leading edge, rounded heavy title. HIG:
    /// Materials, Hierarchy, Color Contrast.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(artwork: track.artwork, size: .large) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
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

            HStack(alignment: .bottom, spacing: 24) {
                CachedAsyncImage(artwork: track.artwork, size: .large) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.currentTheme.panelColor)
                        .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.secondary))
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Track", systemImage: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    Text(track.title)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)

                    if let user = track.user {
                        NavigationLink(value: user) {
                            HStack(spacing: 6) {
                                Text(user.name)
                                    .font(.title3.weight(.medium))
                                if user.isVerified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, themeManager.currentTheme.accentColor)
                                        .font(.subheadline)
                                }
                            }
                            .foregroundColor(themeManager.currentTheme.accentColor)
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
                playerManager.play(track: track)
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
            .help("Play this track")

            Button {
                playerManager.insertNext(track: track)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .help("Queue after the current track")

            Spacer()

            if let plays = track.playCount {
                VStack(alignment: .center, spacing: 2) {
                    Text(formatCount(plays)).font(.title3.weight(.bold))
                    Text("Plays").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 10) {
            if let genre = track.genre, !genre.isEmpty {
                chip(systemImage: "guitars", text: genre)
            }
            if let mood = track.mood, !mood.isEmpty {
                chip(systemImage: "sparkles", text: mood)
            }
            if let released = track.releaseDate, !released.isEmpty {
                chip(systemImage: "calendar", text: String(released.prefix(10)))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.title2.weight(.bold))
            if let desc = track.description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundColor(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This track doesn't have a description.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func chip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundColor(.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
