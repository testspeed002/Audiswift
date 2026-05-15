import SwiftUI
import AppKit

// MARK: - Visualizer Style Enum

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case bars = "Bars"
    case stereometer = "Stereometer"
    case circular = "Circular"
    case spectrogram = "Spectrogram"
    case oscilloscope = "Oscilloscope"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .classic:      return "drop.halffull"
        case .bars:         return "chart.bar.fill"
        case .stereometer:  return "camera.aperture"
        case .circular:     return "circle.hexagongrid.fill"
        case .spectrogram:  return "water.waves"
        case .oscilloscope: return "tv"
        }
    }
}

// MARK: - Main Visualizer View

struct VisualizerView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var analyzer = FFTAnalyzer.shared
    @AppStorage("visualizerStyle") private var selectedStyle: String = VisualizerStyle.classic.rawValue
    @State private var showingTrackDetail = false

    private var style: VisualizerStyle {
        VisualizerStyle(rawValue: selectedStyle) ?? .classic
    }
    
    var body: some View {
        ZStack {
            Color.black

            if playerManager.currentTrack != nil {
                if style == .classic {
                    visualizerSection
                        .padding(.bottom, 210)
                } else {
                    adaptiveBackground
                    visualizerSection
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                        .padding(.bottom, 210)
                }
            } else {
                adaptiveBackground
                noTrackPlaceholder
                    .padding(.bottom, 144)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            VisualizerStylePicker()
                .padding(.bottom, 144)
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
        case .classic:
            ClassicVisualizerView(amplitudes: analyzer.amplitudes, accentColor: themeManager.currentTheme.accentColor)
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
            let ratio = max(1, amplitudes.count / max(1, displayCount))
            
            let itemWidth = geo.size.width / CGFloat(max(1, displayCount))
            let barWidth = max(1, itemWidth * 0.8)
            
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<displayCount, id: \.self) { i in
                    let startIndex = i * ratio
                    let endIndex = min(startIndex + ratio, amplitudes.count)
                    let slice = amplitudes[startIndex..<endIndex]
                    let avgAmp = slice.isEmpty ? 0 : slice.reduce(0, +) / CGFloat(slice.count)
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

    // Time-stamped history: each entry is evicted after `trailDuration` seconds,
    // matching the bar visualizer's 150 ms decay half-life. This makes the
    // stereometer's visual persistence route-independent — it no longer matters
    // whether frames arrive at 12 Hz (Bluetooth) or 30 Hz (built-in speakers).
    private struct HistoryEntry {
        let samples: [CGPoint]
        let timestamp: CFTimeInterval
    }
    @State private var history: [HistoryEntry] = []
    private let trailDuration: CFTimeInterval = 0.150

    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height)
            ZStack {
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
                    let now = CACurrentMediaTime()

                    for entry in history {
                        guard !entry.samples.isEmpty else { continue }
                        let age = now - entry.timestamp
                        // Fade linearly from 1→0 over trailDuration seconds
                        let opacity = max(0, CGFloat(1 - age / trailDuration))

                        var path = Path()
                        var first = true
                        let step = max(1, entry.samples.count / 250)

                        for i in stride(from: 0, to: entry.samples.count, by: step) {
                            let pt = entry.samples[i]
                            let x = midX + pt.x * scale
                            let y = midY - pt.y * scale

                            if first {
                                path.move(to: CGPoint(x: x, y: y))
                                first = false
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        context.stroke(path, with: .color(accentColor.opacity(opacity)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        // Glow on the most recent entry only
                        if entry.timestamp == history.last?.timestamp {
                            var glowContext = context
                            glowContext.addFilter(.shadow(color: accentColor.opacity(0.8), radius: 5))
                            glowContext.stroke(path, with: .color(accentColor.opacity(opacity * 0.5)), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            .onChange(of: stereoSamples) { _, newSamples in
                let now = CACurrentMediaTime()
                history.append(HistoryEntry(samples: newSamples, timestamp: now))
                // Evict entries older than the trail duration
                history.removeAll { now - $0.timestamp > trailDuration }
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
            let baseRadius: CGFloat = minDimension * 0.30
            let maxBarLength: CGFloat = minDimension * 0.18
            let lineWidth = max(2, minDimension * 0.010)
            
            // Focus on bass + mids (bars 0..31 ≈ 11–560 Hz) but stretch that
            // slice across the full bar count via linear interpolation, so the
            // ring keeps its dense petal look while the upper half of the
            // spectrum (cymbals, hi-hats) doesn't get any visual real estate.
            let focusedCount = 128
            let analyzerMinFreq: CGFloat = 11
            let analyzerMaxFreq: CGFloat = 22500
            let curveMinFreq: CGFloat = 11
            let curveMaxFreq: CGFloat = 250
            let logSpan = log(analyzerMaxFreq / analyzerMinFreq)
            let bandCount = amplitudes.count

            let interpolated: [CGFloat] = (0..<focusedCount).map { i in
                guard bandCount > 1 else { return amplitudes.first ?? 0 }
                let t = CGFloat(i) / CGFloat(focusedCount - 1)
                let freq = curveMinFreq + (curveMaxFreq - curveMinFreq) * t
                let barF = log(freq / analyzerMinFreq) / logSpan * CGFloat(bandCount)
                let lo = max(0, min(bandCount - 1, Int(barF.rounded(.down))))
                let hi = max(0, min(bandCount - 1, lo + 1))
                let frac = max(0, min(1, barF - CGFloat(lo)))
                return amplitudes[lo] * (1 - frac) + amplitudes[hi] * frac
            }

            let minAmp = interpolated.min() ?? 0
            let maxAmp = interpolated.max() ?? 1
            let span = max(0.05, maxAmp - minAmp)
            let focused: [CGFloat] = interpolated.map { v in
                let centered = max(0, v - minAmp) / span
                let shaped = pow(centered, 0.7)
                return shaped * 0.85 + v * 0.15
            }

            let mirrored: [CGFloat] = focused + focused.reversed()
            let totalSlots = max(mirrored.count, 1)
            let points: [CGPoint] = (0..<totalSlots).map { i in
                let amp = mirrored[i]
                let radius = baseRadius + max(0, amp) * maxBarLength
                let angle = -.pi / 2 + (CGFloat(i) + 0.5) * (.pi * 2) / CGFloat(totalSlots)
                return CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
            }

            let smoothPath = Path { p in
                guard points.count > 2 else { return }
                func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
                let first = points[0]
                let last  = points[points.count - 1]
                p.move(to: mid(last, first))
                for i in 0..<points.count {
                    let current = points[i]
                    let next = points[(i + 1) % points.count]
                    p.addQuadCurve(to: mid(current, next), control: current)
                }
                p.closeSubpath()
            }

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: baseRadius * 2, height: baseRadius * 2)
                    .position(center)

                smoothPath
                    .fill(accentColor.opacity(0.18))
                    .blendMode(.screen)

                smoothPath
                    .stroke(accentColor.opacity(0.35), lineWidth: lineWidth * 5)
                    .blur(radius: 14)
                    .blendMode(.screen)

                smoothPath
                    .stroke(accentColor.opacity(0.85), lineWidth: lineWidth * 1.6)
                    .blur(radius: 3)
                    .blendMode(.screen)
            }
            .drawingGroup()
        }
    }
}

// MARK: - Spectrogram Visualizer
struct SpectrogramView: View {
    let amplitudes: [CGFloat]
    let accentColor: Color

    private struct SpectrogramEntry {
        let column: [CGFloat]
        let timestamp: CFTimeInterval
    }
    @State private var history: [SpectrogramEntry] = []
    // Timestamp the NEXT column should be stamped with. Columns are placed on a
    // quantized uniform time grid (multiples of 1/columnHz) rather than at raw
    // wall-clock arrival time — raw arrival jitters ±20 ms, and since each
    // column is drawn out to the next column's x, that jitter became visibly
    // uneven column WIDTHS. A uniform grid keeps every column the same width.
    @State private var nextColumnTime: CFTimeInterval = 0
    // Wall-clock window of visible history. 2 s of scroll regardless of how
    // often the audio thread publishes new amplitude frames — built-in
    // speakers and Bluetooth render the same time span on screen.
    private let historyDuration: CFTimeInterval = 2.0
    private let columnHz: Double = 30.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / columnHz)) { _ in
            Canvas { gc, size in
                let now = CACurrentMediaTime()
                let cellHeight = size.height / CGFloat(max(1, amplitudes.count))
                let pxPerSecond = size.width / CGFloat(historyDuration)

                // history is newest-first (index 0 = newest). Each column is
                // drawn from its own x up to the NEXT-newer column's x, so the
                // strip stays gapless even when columns aren't spaced perfectly
                // evenly in time — a fixed column width left visible black slits.
                for (i, entry) in history.enumerated() {
                    let age = now - entry.timestamp
                    guard age >= 0 else { continue }
                    var x = size.width - CGFloat(age) * pxPerSecond
                    let rightX: CGFloat
                    if i == 0 {
                        rightX = size.width
                    } else {
                        let newerAge = now - history[i - 1].timestamp
                        rightX = size.width - CGFloat(max(0, newerAge)) * pxPerSecond
                    }
                    // Skip columns whose right edge has scrolled fully off the
                    // left side. The oldest still-visible column gets its left
                    // edge clamped to 0 so it always paints the left margin —
                    // otherwise a thin black sliver flickers there each frame as
                    // columns age out (the "left-end jitter").
                    if rightX <= 0 { continue }
                    if x < 0 { x = 0 }
                    let barWidth = max(1, rightX - x + 0.5)
                    for (rowIndex, amp) in entry.column.enumerated() {
                        let y = size.height - (CGFloat(rowIndex) * cellHeight) - cellHeight
                        let rect = CGRect(x: x, y: y, width: barWidth, height: cellHeight + 1.5)
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
                        gc.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)
        .onChange(of: amplitudes) { _, newAmps in
            let now = CACurrentMediaTime()
            let interval = 1.0 / columnHz
            if nextColumnTime == 0 { nextColumnTime = now }
            // Only emit a column once wall-clock has reached the next grid slot.
            // amplitudes publishes faster than columnHz, so most calls no-op.
            guard now >= nextColumnTime else { return }
            // Stamp with the GRID time, not `now` — uniform spacing → uniform width.
            history.insert(SpectrogramEntry(column: newAmps, timestamp: nextColumnTime), at: 0)
            nextColumnTime += interval
            // If we've fallen more than one slot behind real time (e.g. a stall
            // or the view was backgrounded), resync rather than rushing to catch up.
            if now - nextColumnTime > interval { nextColumnTime = now + interval }
            // Keep a small margin of already-off-screen columns so the draw
            // loop always has one column to clamp against the left edge.
            history.removeAll { now - $0.timestamp > historyDuration + 0.25 }
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
                    let displayCount = min(samples.count, Int(size.width * 0.8))
                    let step = max(1, samples.count / max(1, displayCount))
                    
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

// MARK: - Classic Plasma Visualizer

struct ClassicVisualizerView: View {
    let amplitudes: [CGFloat]
    let accentColor: Color

    private static let particleCount = 70

    @State private var particles: [Particle] = []
    @State private var lastTick: TimeInterval = 0
    @State private var lastSize: CGSize = .zero

    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var direction: CGPoint
        var baseSpeed: CGFloat
        let size: CGFloat
        let hueOffset: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { geo in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = max(1, amplitudes.count)
                let midEnd  = min(24, count)
                let highRange = amplitudes.dropFirst(midEnd)
                let high = highRange.isEmpty ? 0 : Double(highRange.reduce(0, +)) / Double(highRange.count)

                let ringBassEnd = min(19, count)
                let ringBass = Double(amplitudes.prefix(ringBassEnd).reduce(0, +)) / Double(ringBassEnd)

                let particleStart = min(5, count)
                let particleEnd   = min(24, count)
                let particleSlice = amplitudes.dropFirst(particleStart).prefix(particleEnd - particleStart)
                let particleEnergy = particleSlice.isEmpty
                    ? 0
                    : Double(particleSlice.reduce(0, +)) / Double(particleSlice.count)

                let w  = geo.size.width
                let h  = geo.size.height
                let cx = w / 2
                let cy = h / 2
                let R  = min(w, h)

                let blobBoundaries = [0, 13, 26, 39, 52, count]
                let blobAmps: [Double] = (0..<5).map { i in
                    let lo = min(blobBoundaries[i], count)
                    let hi = min(blobBoundaries[i + 1], count)
                    guard hi > lo else { return 0 }
                    let slice = amplitudes[lo..<hi]
                    return Double(slice.reduce(0, +)) / Double(slice.count)
                }

                ZStack {
                    ZStack {
                        Color.black
                        ForEach(0..<5, id: \.self) { i in
                            let amp    = blobAmps[i]
                            let phase  = t * (0.18 + Double(i) * 0.07) + Double(i) * 1.7
                            let radius = R * (0.40 + 0.15 * CGFloat(sin(phase)) + 0.40 * CGFloat(amp))
                            let x      = cx + CGFloat(cos(phase * 1.10 + Double(i))) * w * 0.26
                            let y      = cy + CGFloat(sin(phase * 1.30 + Double(i) * 0.7)) * h * 0.26
                            let hue    = (t * 0.05 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1.0)
                            let color  = Color(hue: hue, saturation: 0.9, brightness: 0.75)

                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [color.opacity(0.6), color.opacity(0.0)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(radius, 1)
                                    )
                                )
                                .frame(width: radius * 2, height: radius * 2)
                                .position(x: x, y: y)
                                .blendMode(.screen)
                        }

                        let ringSize = R * (0.35 + CGFloat(ringBass) * 0.6)
                        Circle()
                            .stroke(
                                accentColor.opacity(0.35 + 0.35 * high),
                                lineWidth: 2 + CGFloat(ringBass) * 6
                            )
                            .frame(width: ringSize, height: ringSize)
                            .position(x: cx, y: cy)
                            .blur(radius: 4)
                            .blendMode(.screen)
                    }
                    .compositingGroup()
                    .blur(radius: 18)

                    Canvas { ctx, size in
                        for p in particles {
                            let s = p.size
                            let rect = CGRect(x: p.position.x - s/2,
                                              y: p.position.y - s/2,
                                              width: s, height: s)
                            let hue  = (t * 0.06 + p.hueOffset).truncatingRemainder(dividingBy: 1.0)
                            let halo = Color(hue: hue, saturation: 0.5, brightness: 1.0)
                            var sub = ctx
                            sub.addFilter(.blur(radius: 1.2))
                            sub.fill(Path(ellipseIn: rect), with: .color(halo.opacity(0.85)))
                            sub.fill(Path(ellipseIn: rect.insetBy(dx: s * 0.3, dy: s * 0.3)),
                                     with: .color(.white.opacity(0.95)))
                        }
                    }
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .onChange(of: t) { _, now in
                    advanceParticles(now: now, size: geo.size, energy: particleEnergy)
                }
            }
        }
    }

    private func advanceParticles(now: TimeInterval, size: CGSize, energy: Double) {
        guard size.width > 0, size.height > 0 else { return }

        if particles.isEmpty || size != lastSize {
            particles = (0..<Self.particleCount).map { _ in
                let angle = Double.random(in: 0..<(.pi * 2))
                return Particle(
                    position: CGPoint(x: CGFloat.random(in: 0...size.width),
                                      y: CGFloat.random(in: 0...size.height)),
                    direction: CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle))),
                    baseSpeed: CGFloat.random(in: 1...60),
                    size: CGFloat.random(in: 2.0...4.0),
                    hueOffset: Double.random(in: 0..<1)
                )
            }
            lastSize = size
            lastTick = now
            return
        }

        let dt = max(0, min(0.1, now - lastTick))
        lastTick = now

        let amp = max(0, min(1, energy))
        let kick = amp * amp
        let speedScale = 1.0 + CGFloat(kick) * 14.0

        for i in particles.indices {
            var p = particles[i]
            let v = p.baseSpeed * speedScale
            p.position.x += p.direction.x * v * CGFloat(dt)
            p.position.y += p.direction.y * v * CGFloat(dt)

            if p.position.x < -4 { p.position.x = size.width + 4 }
            if p.position.x > size.width + 4 { p.position.x = -4 }
            if p.position.y < -4 { p.position.y = size.height + 4 }
            if p.position.y > size.height + 4 { p.position.y = -4 }

            particles[i] = p
        }
    }
}

// MARK: - Visualizer Style Picker

struct VisualizerStylePicker: View {
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("visualizerStyle") private var selectedStyle: String = VisualizerStyle.classic.rawValue

    private var style: VisualizerStyle {
        VisualizerStyle(rawValue: selectedStyle) ?? .classic
    }

    var body: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
