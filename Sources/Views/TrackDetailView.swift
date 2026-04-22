import SwiftUI

struct TrackDetailView: View {
    let track: Track
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                // Header Area
                HStack(alignment: .bottom, spacing: 24) {
                    CachedAsyncImage(artwork: track.artwork, size: .large) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(themeManager.currentTheme.panelColor)
                            .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.secondary))
                    }
                    .frame(width: 220, height: 220)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(track.title)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.primary)
                            
                        if let user = track.user {
                            NavigationLink(value: user) {
                                Text(user.name)
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(themeManager.currentTheme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        HStack(spacing: 16) {
                            if let genre = track.genre {
                                Text(genre.uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(themeManager.currentTheme.panelColor)
                                    .cornerRadius(6)
                            }
                            
                            if let created = track.releaseDate {
                                let prefix = created.prefix(10) // Basic YYYY-MM-DD
                                Text("Released: \(prefix)").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Button {
                                playerManager.play(track: track)
                            } label: {
                                Label("Play Track", systemImage: "play.fill")
                                    .font(.headline)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(themeManager.currentTheme.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 40)
                
                Divider()
                    .padding(.horizontal, 30)
                
                // Track Description Area
                VStack(alignment: .leading, spacing: 16) {
                    Text("Description")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let desc = track.description, !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundColor(.primary.opacity(0.85))
                            .textSelection(.enabled)
                    } else {
                        Text("This track does not have a description.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.currentTheme.backgroundColor)
        .navigationTitle("Track Details")
        .overlay(alignment: .topTrailing) {
            Button {
                if let onClose = onClose {
                    onClose()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
            .help("Press ESC or click to close")
        }
    }
}
