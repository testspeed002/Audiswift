import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("visualizerStyle") private var visualizerStyle = VisualizerStyle.classic.rawValue
    @AppStorage("visualizerFramerate") private var visualizerFramerate = 60
    @AppStorage("rememberPlaybackState") private var rememberPlaybackState = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    playbackSection
                    aboutSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .background(themeManager.currentTheme.backgroundColor)
        .frame(width: 500, height: 460)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundColor(themeManager.currentTheme.accentColor)
            Text("Preferences")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var appearanceSection: some View {
        GroupBox("Appearance & Visualizer") {
            VStack(spacing: 12) {
                HStack {
                    Text("Theme")
                    Spacer()
                    Picker("", selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                
                Divider()
                
                HStack {
                    Text("Default Visualizer Style")
                    Spacer()
                    Picker("", selection: $visualizerStyle) {
                        ForEach(VisualizerStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.icon).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                
                Divider()
                
                HStack {
                    Text("Visualizer Framerate")
                    Spacer()
                    Picker("", selection: $visualizerFramerate) {
                        Text("Smooth (60 FPS)").tag(60)
                        Text("Energy Saving (30 FPS)").tag(30)
                    }
                    .labelsHidden()
                }
            }
            .padding(8)
        }
    }
    
    private var playbackSection: some View {
        GroupBox("Playback") {
            VStack(spacing: 12) {
                HStack {
                    Text("Remember playback position on launch")
                    Spacer()
                    Toggle("", isOn: $rememberPlaybackState)
                        .toggleStyle(.switch)
                }
            }
            .padding(8)
        }
    }

    private var aboutSection: some View {
        GroupBox("About Audiswift") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                Text("A high-performance Audius client built with SwiftUI and CoreAudio.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
