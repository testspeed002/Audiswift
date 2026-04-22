import SwiftUI

// MARK: - Visualizer Style Enum

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars = "Bars"
    case stereometer = "Stereometer"
    case circular = "Circular"
    case spectrogram = "Spectrogram"
    case oscilloscope = "Oscilloscope"
    case particles = "Particles"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .bars:         return "chart.bar.fill"
        case .stereometer:  return "camera.aperture"
        case .circular:     return "circle.hexagongrid.fill"
        case .spectrogram:  return "water.waves"
        case .oscilloscope: return "tv"
        case .particles:    return "sparkles"
        }
    }
}

// MARK: - Main Visualizer View

struct VisualizerView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var analyzer = FFTAnalyzer.shared
    @AppStorage("visualizerStyle") private var selectedStyle: String = VisualizerStyle.bars.rawValue
    @State private var showingTrackDetail = false
    
    private var style: VisualizerStyle {
        VisualizerStyle(rawValue: selectedStyle) ?? .bars
    }
    
    var body: some View {
        ZStack {
            // Adaptive / Immersive Background
            adaptiveBackground
            
            if let track = playerManager.currentTrack {
                GeometryReader { geo in
                    let artworkSize = min(max(geo.size.width * 0.25, 120), 250)
                    
                    HStack(spacing: 40) {
                        // Left Half: Artwork + Info
                        HStack(alignment: .center, spacing: 20) {
                            artworkSection(track: track, size: artworkSize)
                            trackInfoSection(track: track)
                        }
                        .frame(width: max(350, geo.size.width * 0.35), alignment: .center)
                        
                        // Right Half: Visualizer + Picker
                        VStack(spacing: 30) {
                            visualizerSection
                                .frame(maxHeight: .infinity)
                                .frame(minHeight: geo.size.height * 0.4)
                            
                            stylePicker
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 120)
                }
            } else {
                // No-track placeholder
                noTrackPlaceholder
            }
        }
        .sheet(isPresented: $showingTrackDetail) {
            if let track = playerManager.currentTrack {
                NavigationStack {
                    TrackDetailView(track: track, onClose: { showingTrackDetail = false })
                        .navigationDestination(for: User.self)     { user     in UserProfileView(user: user) }
                        .navigationDestination(for: Playlist.self) { playlist in PlaylistDetailView(playlist: playlist) }
                        .navigationDestination(for: Track.self)    { track    in TrackDetailView(track: track) }
                }
                .frame(width: 600, height: 500)
                .environmentObject(playerManager)
                .environmentObject(themeManager)
                .presentationBackground(themeManager.currentTheme.backgroundColor)
            }
        }
    }
    
    // MARK: - Adaptive Background
    
    @ViewBuilder
    private var adaptiveBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Animated gradient from accent color
            RadialGradient(
                colors: [
                    themeManager.currentTheme.accentColor.opacity(0.2),
                    themeManager.currentTheme.accentColor.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Artwork
    
    @ViewBuilder
    private func artworkSection(track: Track, size: CGFloat = 300) -> some View {
        CachedAsyncImage(artwork: track.artwork, size: .large) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.2))
                        .foregroundColor(.secondary)
                )
        }
        .frame(width: size, height: size)
        .cornerRadius(24)
        .shadow(color: themeManager.currentTheme.accentColor.opacity(0.4), radius: 40, x: 0, y: 20)
    }
    
    // MARK: - Track Info
    
    @ViewBuilder
    private func trackInfoSection(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(track.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    
                Button {
                    showingTrackDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("View Track Details")
            }
            
            if let user = track.user {
                NavigationLink(value: user) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
                .buttonStyle(.plain)
                .help("View \(user.name)'s profile")
            }
        }
    }
    
    // MARK: - Visualizer Content
    
    @ViewBuilder
    private var visualizerSection: some View {
        switch style {
        case .bars:
            BarSpectrumView(amplitudes: analyzer.amplitudes, colors: themeManager.currentTheme.visualizerColors, accentColor: themeManager.currentTheme.accentColor)
        case .stereometer:
            StereometerView(stereoSamples: analyzer.stereoSamples, accentColor: themeManager.currentTheme.accentColor)
        case .circular:
            CircularVisualizerView(amplitudes: analyzer.amplitudes, accentColor: themeManager.currentTheme.accentColor)
        case .spectrogram:
            SpectrogramView(amplitudes: analyzer.amplitudes, accentColor: themeManager.currentTheme.accentColor)
        case .oscilloscope:
            OscilloscopeView(samples: analyzer.waveformSamples, accentColor: themeManager.currentTheme.accentColor)
        case .particles:
            ParticleFountainView(amplitudes: analyzer.amplitudes, accentColor: themeManager.currentTheme.accentColor)
        }
    }
    
    // MARK: - Style Picker
    
    private var stylePicker: some View {
        HStack(spacing: 16) {
            ForEach(VisualizerStyle.allCases) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStyle = s.rawValue
                    }
                } label: {
                    Image(systemName: s.icon)
                        .font(.system(size: 16))
                        .foregroundColor(style == s ? themeManager.currentTheme.accentColor : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(style == s ? themeManager.currentTheme.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(s.rawValue)
            }
        }
    }
    
    // MARK: - No Track Placeholder
    
    private var noTrackPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary.opacity(0.5))
                .symbolEffect(.pulse, options: .repeating)
            
            Text("Nothing Playing")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Button {
                // Navigate to trending
                LibraryViewModel.shared.selectTab(.trending)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Browse Trending")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(themeManager.currentTheme.accentColor.opacity(0.15))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Bar Spectrum Visualizer

struct BarSpectrumView: View {
    let amplitudes: [CGFloat]
    let colors: [Color]
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 500
            let displayCount = isWide ? amplitudes.count : amplitudes.count / 2
            let ratio = amplitudes.count / displayCount
            
            let itemWidth = geo.size.width / CGFloat(displayCount)
            let spacing = itemWidth * 0.2
            let barWidth = max(1, itemWidth * 0.8)
            
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<displayCount, id: \.self) { i in
                    let startIndex = i * ratio
                    let endIndex = min(startIndex + ratio, amplitudes.count)
                    let slice = amplitudes[startIndex..<endIndex]
                    let avgAmp = slice.reduce(0, +) / CGFloat(slice.count)
                    let amp = min(avgAmp, 1.0)
                    
                    let barHeight = max(4, geo.size.height * amp)
                    let xOffset = CGFloat(i) * itemWidth
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                        .frame(width: barWidth, height: barHeight)
                        .shadow(color: accentColor.opacity(amp > 0.3 ? amp * 0.3 : 0), radius: 5)
                        .offset(x: xOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .drawingGroup()
        }
    }
}

// MARK: - Stereometer Visualizer

struct StereometerView: View {
    let stereoSamples: [CGPoint]
    let accentColor: Color
    
    @State private var history: [[CGPoint]] = []
    private let historyCount = 4
    
    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height)
            ZStack {
                // Subtle circular background guides
                Circle()
                    .stroke(accentColor.opacity(0.05), lineWidth: 1)
                    .frame(width: minDimension * 0.9, height: minDimension * 0.9)
                Circle()
                    .stroke(accentColor.opacity(0.03), lineWidth: 1)
                    .frame(width: minDimension * 0.45, height: minDimension * 0.45)
                
                Canvas { context, size in
                    let midX = size.width / 2
                    let midY = size.height / 2
                    let scale = minDimension * 0.45
                    
                    for (index, samples) in history.enumerated() {
                        guard !samples.isEmpty else { continue }
                        let opacity = CGFloat(index + 1) / CGFloat(history.count)
                        
                        var path = Path()
                        var first = true
                        let step = max(1, samples.count / 250)
                        
                        for i in stride(from: 0, to: samples.count, by: step) {
                            let pt = samples[i]
                            let x = midX + pt.x * scale
                            let y = midY - pt.y * scale
                            
                            if first {
                                path.move(to: CGPoint(x: x, y: y))
                                first = false
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        
                        let color = accentColor.opacity(opacity)
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        
                        if index == history.count - 1 {
                            // Add glow effect only to the newest frame
                            var glowContext = context
                            glowContext.addFilter(.shadow(color: accentColor.opacity(0.8), radius: 5))
                            glowContext.stroke(path, with: .color(accentColor.opacity(0.5)), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: stereoSamples) { _, newSamples in
                history.append(newSamples)
                if history.count > historyCount {
                    history.removeFirst()
                }
            }
        }
    }
}

// MARK: - Circular Radial Visualizer

struct CircularVisualizerView: View {
    let amplitudes: [CGFloat]
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let minDimension = min(geometry.size.width, geometry.size.height)
            let baseRadius: CGFloat = minDimension * 0.18
            let maxBarLength: CGFloat = minDimension * 0.30
            let lineWidth = max(2, minDimension * 0.008)
            
            ZStack {
                // Center Circle
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: baseRadius * 2, height: baseRadius * 2)
                    .position(center)
                
                let totalBars = amplitudes.count * 2
                ForEach(0..<totalBars, id: \.self) { i in
                    let isRightHalf = i < amplitudes.count
                    let ampIndex = isRightHalf ? amplitudes.count - 1 - i : i - amplitudes.count
                    let amp = amplitudes[ampIndex]
                    let barLength = max(4, amp * maxBarLength)
                    
                    let angleStep = (.pi * 2) / CGFloat(totalBars)
                    let angleOffset = .pi / 2 + (.pi / CGFloat(totalBars))
                    let angle = CGFloat(i) * angleStep + angleOffset
                    
                    Capsule()
                        .fill(accentColor.opacity(0.4 + amp * 0.6))
                        .frame(width: lineWidth, height: barLength)
                        .shadow(color: accentColor.opacity(amp > 0.5 ? 0.5 : 0), radius: 3)
                        .offset(y: -(baseRadius + barLength / 2))
                        .rotationEffect(Angle(radians: Double(angle) + .pi / 2))
                        .position(center)
                }
            }
            .drawingGroup()
        }
    }
}

// MARK: - Spectrogram Visualizer
struct SpectrogramView: View {
    let amplitudes: [CGFloat]
    let accentColor: Color
    
    @State private var history: [[CGFloat]] = []
    private let historyCount = 60
    
    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(historyCount)
            let cellHeight = size.height / CGFloat(amplitudes.count)
            
            for (colIndex, column) in history.enumerated() {
                let x = size.width - (CGFloat(colIndex) * barWidth) - barWidth
                for (rowIndex, amp) in column.enumerated() {
                    let y = size.height - (CGFloat(rowIndex) * cellHeight) - cellHeight
                    let rect = CGRect(x: x, y: y, width: barWidth + 1.5, height: cellHeight + 1.5)
                    
                    // Heatmap color logic (dark -> blue -> purple -> pink -> white)
                    let intensity = Double(amp)
                    let color: Color
                    if intensity < 0.2 {
                        color = Color.blue.opacity(intensity * 2)
                    } else if intensity < 0.5 {
                        color = accentColor.opacity(intensity)
                    } else if intensity < 0.8 {
                        color = Color.pink.opacity(intensity)
                    } else {
                        color = Color.white.opacity(intensity)
                    }
                    
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)
        .onChange(of: amplitudes) { _, newAmps in
            history.insert(newAmps, at: 0)
            if history.count > historyCount {
                history.removeLast()
            }
        }
    }
}

// MARK: - Oscilloscope Visualizer
struct OscilloscopeView: View {
    let samples: [CGFloat]
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // CRT Background Grid
                VStack(spacing: geometry.size.height / 8) {
                    ForEach(0..<9, id: \.self) { _ in Rectangle().fill(accentColor.opacity(0.1)).frame(height: 1) }
                }
                HStack(spacing: geometry.size.width / 8) {
                    ForEach(0..<9, id: \.self) { _ in Rectangle().fill(accentColor.opacity(0.1)).frame(width: 1) }
                }
                
                Canvas { context, size in
                    guard !samples.isEmpty else { return }
                    
                    let midY = size.height / 2
                    let scaleY = size.height * 0.4
                    
                    var path = Path()
                    let displayCount = min(samples.count, Int(size.width * 0.8)) // Higher resolution
                    let step = max(1, samples.count / displayCount)
                    
                    for i in 0..<displayCount {
                        let sampleIndex = min(i * step, samples.count - 1)
                        let val = samples[sampleIndex]
                        
                        let x = CGFloat(i) / CGFloat(displayCount) * size.width
                        let y = midY - val * scaleY
                        
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    
                    context.stroke(path, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    
                    // Add glow effect
                    var glowContext = context
                    glowContext.addFilter(.shadow(color: accentColor.opacity(0.8), radius: 4))
                    glowContext.stroke(path, with: .color(accentColor.opacity(0.5)), lineWidth: 1.5)
                }
            }
        }
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Particle Fountain Visualizer
struct Particle: Identifiable {
    let id = UUID()
    let spawnPosition: CGPoint
    let initialVelocity: CGPoint
    let spawnTime: Date
    let maxLife: Double
    let color: Color
    let size: CGFloat
}

struct ParticleFountainView: View {
    let amplitudes: [CGFloat]
    let accentColor: Color
    
    @State private var particles: [Particle] = []
    
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    for particle in particles {
                        let elapsed = now.timeIntervalSince(particle.spawnTime)
                        if elapsed >= particle.maxLife { continue }
                        
                        let opacity = 1.0 - (elapsed / particle.maxLife)
                        let x = particle.spawnPosition.x + particle.initialVelocity.x * elapsed * 60
                        let y = particle.spawnPosition.y + particle.initialVelocity.y * elapsed * 60 + 0.5 * 0.2 * pow(elapsed * 60, 2)
                        
                        let rect = CGRect(
                            x: x - particle.size/2,
                            y: y - particle.size/2,
                            width: particle.size,
                            height: particle.size
                        )
                        
                        context.fill(Path(ellipseIn: rect), with: .color(particle.color.opacity(opacity)))
                    }
                }
            }
            .onChange(of: amplitudes) { _, newAmps in
                let now = Date()
                // Clean up dead particles
                particles.removeAll { now.timeIntervalSince($0.spawnTime) >= $0.maxLife }
                
                let avgAmp = newAmps.reduce(0, +) / CGFloat(newAmps.count)
                if avgAmp > 0.15 {
                    let spawnCount = Int(avgAmp * 15)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    
                    var newParticles = [Particle]()
                    for _ in 0..<spawnCount {
                        let angle = CGFloat.random(in: -CGFloat.pi...CGFloat.pi)
                        let speed = CGFloat.random(in: 2...8) * avgAmp * 3
                        let vX = cos(angle) * speed
                        let vY = sin(angle) * speed - 2 // Upward bias
                        
                        newParticles.append(Particle(
                            spawnPosition: center,
                            initialVelocity: CGPoint(x: vX, y: vY),
                            spawnTime: now,
                            maxLife: Double.random(in: 1.0...2.5),
                            color: accentColor,
                            size: CGFloat.random(in: 2...6)
                        ))
                    }
                    particles.append(contentsOf: newParticles)
                }
            }
        }
    }
}
