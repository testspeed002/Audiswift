import Foundation
import CoreMedia
import Accelerate
import AVFoundation
import SwiftUI

final class FFTAnalyzer: ObservableObject {
    static let shared = FFTAnalyzer()
    
    @Published var amplitudes: [CGFloat] = Array(repeating: 0.03, count: 64)
    @Published var waveformSamples: [CGFloat] = [] // For waveform mode
    @Published var stereoSamples: [CGPoint] = [] // For stereoscope
    
    private let fftSize: vDSP_Length = 4096
    private let barCount = 64
    private var fftSetup: FFTSetup?
    
    var sampleRate: Float = 44100.0
    var channelCount: UInt32 = 2

    /// Continuous mono ring buffer. Trimmed once samples fall behind `readOffset`,
    /// matching `OfflineFFTAnalyzer`'s sliding-window approach.
    private var sampleBuffer = [Float]()
    /// Absolute index where the next FFT window starts. Advances by `hopSize` per emit.
    private var readOffset: Int = 0
    /// Hop size between successive FFT windows. Set in `prepare` once `sampleRate`
    /// is known. 44.1 kHz / 60 fps ≈ 735 samples → live FFT cadence ≈ 60 Hz, matching
    /// the offline exporter for a perfectly smooth visualizer.
    private var hopSize: Int = 735
    /// Guards the audio-thread → main-thread handoff. The audio thread appends
    /// to `pendingAmps`/`pendingWaveformAppend`/`pendingStereoAppend` under this
    /// lock; `flushPublish` drains them on the main thread.
    private let publishLock = NSLock()
    private var pendingAmps: [Float] = []
    /// Raw waveform/stereo samples deposited by the audio (tap) thread under
    /// `publishLock`. `flushPublish` drains these on the main thread. The audio
    /// thread NEVER owns the playout rings below — it only appends here — so
    /// main-thread trimming/windowing can't race the tap thread.
    private var pendingWaveformAppend: [CGFloat] = []
    private var pendingStereoAppend: [CGPoint] = []
    /// Wall-clock timestamp of the last `flushPublish`. Used to compute
    /// time-based smoothing so the visual decay rate stays constant whether
    /// callbacks arrive at 60 Hz (built-in speakers, small buffers) or 12 Hz
    /// (Bluetooth, larger buffers).
    private var lastPublishTimestamp: CFTimeInterval = 0
    /// Main-thread-owned jitter buffer for the waveform/stereo visualizers.
    /// Audio callbacks arrive in bursts whose size depends on the route
    /// (Bluetooth ships ~93 ms chunks ~11×/sec; built-in speakers ship ~5 ms
    /// chunks ~190×/sec). `flushPublish` drains the pending appends into these
    /// rings and scrolls a fixed-length display window through them at a
    /// constant rate, so the stereometer/oscilloscope scan speed is identical
    /// on every audio route. Only touched on the main actor — no data race.
    private var waveformRing: [CGFloat] = []
    private var stereoRing: [CGPoint] = []
    /// Fractional sample index (into the rings) of the right edge of the
    /// displayed window. Advances by exactly `sampleRate / publishHz` per frame.
    private var playoutCursor: Double = 0
    /// The playout cursor stays this far behind the freshest sample so the
    /// steady 60 Hz consumer never starves between bursty audio callbacks —
    /// sized larger than one Bluetooth chunk (~93 ms).
    private let jitterDepthSeconds: Double = 0.18
    /// Length of the waveform/stereo window actually shown on screen.
    private let displayWindowSeconds: Double = 0.085
    /// Main-thread timer that drives `flushPublish` at a fixed cadence. The
    /// audio thread only writes to the pending buffers under `publishLock`;
    /// this timer reads them on a route-independent schedule. Without this,
    /// the publish rate was gated by audio callback arrival — BT routes
    /// (~12 callbacks/sec, 4096-sample chunks ≈ 93 ms each) couldn't reach
    /// the 30–60 Hz design target, so the stereometer/oscilloscope
    /// trail/decay TIMING differed from built-in speakers (~190 callbacks/sec).
    /// At 60 Hz here, amplitude smoothing continues between BT callbacks and
    /// history-based views (stereometer/spectrogram) see consistent wall-clock
    /// cadence on every route.
    private var publishTimer: Timer?
    private let publishHz: Double = 60.0

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
        startPublishTimer()
    }

    deinit {
        publishTimer?.invalidate()
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    private func startPublishTimer() {
        let interval = 1.0 / publishHz
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushPublish() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        publishTimer = timer
    }
    
    func attachTap(to playerItem: AVPlayerItem) {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in },
            prepare: { tap, maxFrames, processingFormat in
                let clientInfo = MTAudioProcessingTapGetStorage(tap)
                let analyzer = Unmanaged<FFTAnalyzer>.fromOpaque(clientInfo).takeUnretainedValue()
                analyzer.sampleRate = Float(processingFormat.pointee.mSampleRate)
                analyzer.channelCount = processingFormat.pointee.mChannelsPerFrame
                // Lock FFT cadence to the user-selected framerate (default 60 Hz) for buttery-smooth motion.
                let fps = UserDefaults.standard.integer(forKey: "visualizerFramerate")
                let actualFPS = fps > 0 ? fps : 60
                analyzer.hopSize = max(1, Int(analyzer.sampleRate) / actualFPS)
            },
            unprepare: { tap in },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                if status != noErr { return }
                
                let clientInfo = MTAudioProcessingTapGetStorage(tap)
                let analyzer = Unmanaged<FFTAnalyzer>.fromOpaque(clientInfo).takeUnretainedValue()
                analyzer.processAudio(bufferList: bufferListInOut, frameCount: UInt32(numberFrames))
            }
        )
        
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        
        if status == noErr, let tapRef = tap {
            Task { @MainActor in
                do {
                    if let audioTrack = try await playerItem.asset.loadTracks(withMediaType: .audio).first {
                        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
                        inputParams.audioTapProcessor = tapRef
                        let audioMix = AVMutableAudioMix()
                        audioMix.inputParameters = [inputParams]
                        playerItem.audioMix = audioMix
                    }
                } catch {
#if DEBUG
                    print("[FFTAnalyzer] Failed to setup audio mix tap: \(error)")
#endif
                }
            }
        }
    }
    
    func processAudio(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        guard fftSetup != nil, frameCount > 0 else { return }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        
        let totalFrames = Int(frameCount)
        let isInterleaved = buffer.mNumberChannels > 1
        let floatData = data.assumingMemoryBound(to: Float.self)
        
        var stereoPts = [CGPoint]()
        stereoPts.reserveCapacity(totalFrames)
        
        var fullPcmBuffer = [Float](repeating: 0, count: totalFrames)
        if isInterleaved {
            for i in 0..<totalFrames {
                let left = floatData[i * 2]
                let right = floatData[i * 2 + 1]
                fullPcmBuffer[i] = (left + right) * 0.5
                stereoPts.append(CGPoint(x: CGFloat(left), y: CGFloat(right)))
            }
        } else if buffers.count >= 2, let rightData = buffers[1].mData {
            let rightFloatData = rightData.assumingMemoryBound(to: Float.self)
            for i in 0..<totalFrames {
                let left = floatData[i]
                let right = rightFloatData[i]
                fullPcmBuffer[i] = (left + right) * 0.5
                stereoPts.append(CGPoint(x: CGFloat(left), y: CGFloat(right)))
            }
        } else {
            for i in 0..<totalFrames {
                let val = floatData[i]
                fullPcmBuffer[i] = val
                stereoPts.append(CGPoint(x: CGFloat(val), y: CGFloat(val)))
            }
        }
        
        // Append new samples to the running buffer. We trim AFTER consuming below
        // (sliding-window approach) so each FFT iteration sees a different window.
        sampleBuffer.append(contentsOf: fullPcmBuffer)

        let n: Int = Int(fftSize)

        // Sliding FFT: emit one frame per `hopSize` new samples. Multiple emissions
        // per audio callback when the buffer is large; zero when it's smaller than
        // a hop. Targets ~60 Hz overall cadence, matching the offline exporter.
        var latestAmps: [Float]? = nil
        while readOffset + n <= sampleBuffer.count {
            var pcmBuffer = Array(sampleBuffer[readOffset..<(readOffset + n)])
            readOffset += hopSize
            if let amps = computeBands(into: &pcmBuffer) {
                latestAmps = amps
            }
        }

        // Bound memory: keep at most one window of context behind the read pointer.
        let keepFrom = max(0, readOffset - n)
        if keepFrom > 0 {
            sampleBuffer.removeFirst(keepFrom)
            readOffset -= keepFrom
        }

        // Deposit raw waveform/stereo samples + the freshest FFT frame for the
        // main-thread `flushPublish` to drain. The audio thread only appends
        // here — it never owns the playout rings — so the 60 Hz consumer can
        // trim and window them without racing this thread.
        publishLock.lock()
        pendingWaveformAppend.append(contentsOf: fullPcmBuffer.map { CGFloat($0) })
        pendingStereoAppend.append(contentsOf: stereoPts)
        if let amps = latestAmps { pendingAmps = amps }
        publishLock.unlock()
    }

    /// Run one FFT pass over `pcm` (already mono, `fftSize` samples) and return the
    /// 64 normalized frequency bands. Mutates `pcm` in place to apply the Hann window.
    /// Returns nil if `fftSetup` is unavailable.
    private func computeBands(into pcm: inout [Float]) -> [Float]? {
        guard let setup = fftSetup else { return nil }
        let n = Int(fftSize)
        
        // Apply Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(pcm, 1, window, 1, &pcm, 1, vDSP_Length(n))
        
        let halfSize = n / 2
        var realP = [Float](repeating: 0.0, count: halfSize)
        var imagP = [Float](repeating: 0.0, count: halfSize)
        
        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        
        // Use withUnsafeMutableBufferPointer to fix pointer safety warnings
        realP.withUnsafeMutableBufferPointer { realBuffer in
            imagP.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                
                pcm.withUnsafeBytes { ptr in
                    vDSP_ctoz(ptr.bindMemory(to: DSPComplex.self).baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                
                vDSP_fft_zrip(setup, &splitComplex, 1, vDSP_Length(log2(Float(n))), FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        
        var normalizedMags = [Float](repeating: 0.0, count: halfSize)
        var scalar: Float = 1.0 / (2.0 * Float(n))
        vDSP_vsmul(magnitudes, 1, &scalar, &normalizedMags, 1, vDSP_Length(halfSize))
        
        let minDB: Float = -75.0
        let maxDB: Float = 6.0
        var newAmps = [Float](repeating: 0.0, count: barCount)
        
        let nyquist = sampleRate / 2.0
        // Cover the full audible spectrum (sub-bass through ultrasonic) so the
        // visualizer responds to absolutely everything in the signal.
        let minFreq: Float = 11.0
        let maxFreq: Float = min(22500.0, nyquist)
        
        for i in 0..<barCount {
            let lowerFreq = minFreq * pow(maxFreq / minFreq, Float(i) / Float(barCount))
            let upperFreq = minFreq * pow(maxFreq / minFreq, Float(i + 1) / Float(barCount))
            
            // Calculate center frequency for smooth interpolation in low frequencies
            let centerFreq = minFreq * pow(maxFreq / minFreq, (Float(i) + 0.5) / Float(barCount))
            let floatBin = (centerFreq / nyquist) * Float(halfSize)
            
            let widthInBins = (upperFreq - lowerFreq) / nyquist * Float(halfSize)
            
            let average: Float
            if widthInBins <= 1.5 {
                // Low frequencies: Bins are too wide, so interpolate between bins to prevent bars from "sticking"
                let lowerBin = min(max(Int(floor(floatBin)), 0), halfSize - 2)
                let fraction = floatBin - Float(lowerBin)
                let interpolatedMag = normalizedMags[lowerBin] * (1.0 - fraction) + normalizedMags[lowerBin + 1] * fraction
                average = interpolatedMag + 1e-15
            } else {
                // High frequencies: Average over the bin range to capture all peaks
                let startBin = max(0, Int((lowerFreq / nyquist) * Float(halfSize)))
                let endBin = min(halfSize, Int((upperFreq / nyquist) * Float(halfSize)))
                let safeEndBin = max(startBin + 1, endBin)
                
                var sum: Float = 0.0
                for j in startBin..<safeEndBin {
                    sum += normalizedMags[j]
                }
                average = (sum / Float(safeEndBin - startBin)) + 1e-15
            }
            
            var dbVal = 20 * log10(average)
            
            if dbVal < minDB { dbVal = minDB }
            if dbVal > maxDB { dbVal = maxDB }
            if dbVal.isNaN { dbVal = minDB }
            
            let normalized = (dbVal - minDB) / (maxDB - minDB)
            
            // Reduced tilt to prevent high-frequency overboosting (A5)
            let frequencyTilt = 1.0 + Float(i) * 0.015
            
            newAmps[i] = min(max(normalized * frequencyTilt, 0.05), 1.0)
        }

        return newAmps
    }

    /// MainActor-only: drain the audio thread's pending samples, scroll the
    /// waveform/stereo display window at a constant rate, and apply asymmetric
    /// attack/decay smoothing to `amplitudes`. Driven by `publishTimer` at a
    /// fixed 60 Hz so every visual's timing is independent of the audio route.
    @MainActor
    private func flushPublish() {
        publishLock.lock()
        let amps = pendingAmps
        let newWaveform = pendingWaveformAppend
        let newStereo = pendingStereoAppend
        pendingWaveformAppend.removeAll(keepingCapacity: true)
        pendingStereoAppend.removeAll(keepingCapacity: true)
        publishLock.unlock()

        guard AudioPlayerManager.shared.isPlaying else { return }

        // ===== Waveform / stereo: constant-rate playout from a jitter buffer =====
        // The audio thread delivers samples in route-dependent bursts. Draining
        // them into a ring and scrolling a fixed window through it at exactly
        // sampleRate/publishHz samples per frame makes the stereometer and
        // oscilloscope scan at the same speed on Bluetooth and built-in output.
        waveformRing.append(contentsOf: newWaveform)
        stereoRing.append(contentsOf: newStereo)
        // Hard cap so a stalled consumer can't grow the rings without bound.
        let ringCap = Int(Double(sampleRate) * 2.0)
        if waveformRing.count > ringCap {
            let drop = waveformRing.count - ringCap
            waveformRing.removeFirst(drop)
            playoutCursor -= Double(drop)
        }
        if stereoRing.count > ringCap {
            stereoRing.removeFirst(stereoRing.count - ringCap)
        }

        let windowSamples = max(256, Int(Double(sampleRate) * displayWindowSeconds))
        let ringCount = min(waveformRing.count, stereoRing.count)
        if ringCount > windowSamples {
            // Advance the window at a constant rate, then clamp so it never
            // runs past the freshest audio nor falls behind the buffer.
            let step = Double(sampleRate) / publishHz
            let jitterSamples = Double(sampleRate) * jitterDepthSeconds
            playoutCursor += step
            let minCursor = Double(windowSamples)
            let maxCursor = max(minCursor, Double(ringCount) - jitterSamples)
            playoutCursor = min(max(playoutCursor, minCursor), maxCursor)

            let endIdx = min(ringCount, max(windowSamples, Int(playoutCursor)))
            let startIdx = max(0, endIdx - windowSamples)
            let windowWave = Array(waveformRing[startIdx..<endIdx])
            let windowStereo = Array(stereoRing[startIdx..<endIdx])

            // Downsample for cheap Canvas drawing — a 4096-point stroked Path
            // at 60 Hz is the actual main-thread bottleneck.
            let waveformTarget = 512
            let stereoTarget = 768
            let wStride = max(1, windowWave.count / waveformTarget)
            let sStride = max(1, windowStereo.count / stereoTarget)
            self.waveformSamples = stride(from: 0, to: windowWave.count, by: wStride).map { windowWave[$0] }
            self.stereoSamples = stride(from: 0, to: windowStereo.count, by: sStride).map { windowStereo[$0] }

            // Drop history we've already scrolled past (keep one window of slack).
            let keep = startIdx - windowSamples
            if keep > 0 {
                waveformRing.removeFirst(min(keep, waveformRing.count))
                stereoRing.removeFirst(min(keep, stereoRing.count))
                playoutCursor -= Double(keep)
            }
        }

        // ===== Amplitude bars: time-based asymmetric attack/decay smoothing =====
        // Half-life formulation keeps the visual attack/decay rate constant
        // regardless of publish cadence.
        let now = CACurrentMediaTime()
        let dt: CFTimeInterval = lastPublishTimestamp == 0
            ? 1.0 / 60.0
            : min(0.25, now - lastPublishTimestamp)
        lastPublishTimestamp = now
        let attackHalfLife: CFTimeInterval = 0.030
        let decayHalfLife: CFTimeInterval  = 0.150
        let attackAlpha = CGFloat(1 - pow(0.5, dt / attackHalfLife))
        let decayAlpha  = CGFloat(1 - pow(0.5, dt / decayHalfLife))

        withAnimation(.interactiveSpring()) {
            if amps.count == self.barCount {
                for i in 0..<self.barCount {
                    let current = self.amplitudes[i]
                    let new = CGFloat(amps[i])
                    let alpha = new > current ? attackAlpha : decayAlpha
                    self.amplitudes[i] = current + (new - current) * alpha
                }
            }
        }
    }
    
    @MainActor
    func reset() {
        lastPublishTimestamp = 0
        // The playout rings are main-thread owned, so clearing them here is
        // race-free. The pending append queues are shared with the audio tap
        // thread, so they're cleared under `publishLock`. `sampleBuffer` stays
        // untouched — it's the audio thread's and refills in <100 ms anyway.
        playoutCursor = 0
        waveformRing.removeAll(keepingCapacity: true)
        stereoRing.removeAll(keepingCapacity: true)
        publishLock.lock()
        pendingWaveformAppend.removeAll(keepingCapacity: true)
        pendingStereoAppend.removeAll(keepingCapacity: true)
        publishLock.unlock()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            for i in 0..<barCount {
                self.amplitudes[i] = 0.05
            }
            self.waveformSamples = []
            self.stereoSamples = []
        }
    }
}
