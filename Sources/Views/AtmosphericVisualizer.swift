import SwiftUI

/// A subtle, ambient version of the visualizer designed to run in the background
/// of other views (like Home or Track Detail) without being distracting.
struct AtmosphericVisualizer: View {
    @ObservedObject private var analyzer = FFTAnalyzer.shared
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var playerManager: AudioPlayerManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base subtle gradient that moves slightly with bass
                let bass = analyzer.amplitudes.prefix(8).reduce(0, +) / 8.0
                let glowScale = 1.0 + (bass * 0.2)
                
                RadialGradient(
                    colors: [
                        themeManager.currentTheme.accentColor.opacity(0.12 * Double(glowScale)),
                        themeManager.currentTheme.accentColor.opacity(0.04),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.8 * glowScale
                )
                .blur(radius: 40)
                
                // Subtle moving "aurora" blobs based on different frequency bands
                ForEach(0..<3) { i in
                    AuroraBlob(
                        index: i,
                        amplitudes: analyzer.amplitudes,
                        accentColor: themeManager.currentTheme.accentColor,
                        size: geo.size
                    )
                }
            }
            .opacity(playerManager.isPlaying ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 1.0), value: playerManager.isPlaying)
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }
}

private struct AuroraBlob: View {
    let index: Int
    let amplitudes: [CGFloat]
    let accentColor: Color
    let size: CGSize
    
    var body: some View {
        let bandSize = amplitudes.count / 3
        let start = index * bandSize
        let slice = amplitudes[start..<min(start + bandSize, amplitudes.count)]
        let amp = slice.isEmpty ? 0 : slice.reduce(0, +) / CGFloat(slice.count)
        
        let xOffset = CGFloat(index - 1) * (size.width * 0.3)
        let yOffset = (amp * 40.0) - 20.0
        
        Circle()
            .fill(accentColor.opacity(0.06 + Double(amp * 0.1)))
            .frame(width: size.width * 0.6, height: size.width * 0.6)
            .scaleEffect(1.0 + amp * 0.3)
            .offset(x: xOffset, y: yOffset)
            .blur(radius: 60)
            .blendMode(.screen)
    }
}
