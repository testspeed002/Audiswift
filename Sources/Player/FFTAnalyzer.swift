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
    
    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
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
        guard let setup = fftSetup, frameCount > 0 else { return }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        
        let n: Int = Int(fftSize)
        guard frameCount >= n else { return }
        
        let totalFrames = Int(frameCount)
        
        // Handle interleaved stereo or mono
        let isInterleaved = buffer.mNumberChannels > 1
        let floatData = data.assumingMemoryBound(to: Float.self)
        
        var stereoPts = [CGPoint]()
        stereoPts.reserveCapacity(totalFrames)
        
        var fullPcmBuffer = [Float](unsafeUninitializedCapacity: totalFrames) { buf, initCount in
            if isInterleaved {
                for i in 0..<totalFrames {
                    let left = floatData[i * 2]
                    let right = floatData[i * 2 + 1]
                    buf[i] = (left + right) * 0.5
                    stereoPts.append(CGPoint(x: CGFloat(left), y: CGFloat(right)))
                }
            } else if buffers.count >= 2, let rightData = buffers[1].mData {
                let rightFloatData = rightData.assumingMemoryBound(to: Float.self)
                for i in 0..<totalFrames {
                    let left = floatData[i]
                    let right = rightFloatData[i]
                    buf[i] = (left + right) * 0.5
                    stereoPts.append(CGPoint(x: CGFloat(left), y: CGFloat(right)))
                }
            } else {
                for i in 0..<totalFrames {
                    let val = floatData[i]
                    buf[i] = val
                    stereoPts.append(CGPoint(x: CGFloat(val), y: CGFloat(val)))
                }
            }
            initCount = totalFrames
        }
        // Expose all frames to the UI for smooth continuous rendering
        let currentWaveform = fullPcmBuffer.map { CGFloat($0) }
        
        // Only use the first `fftSize` samples for the actual FFT analysis
        var pcmBuffer = Array(fullPcmBuffer.prefix(n))
        
        // Apply Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(pcmBuffer, 1, window, 1, &pcmBuffer, 1, vDSP_Length(n))
        
        let halfSize = n / 2
        var realP = [Float](repeating: 0.0, count: halfSize)
        var imagP = [Float](repeating: 0.0, count: halfSize)
        
        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        
        // Use withUnsafeMutableBufferPointer to fix pointer safety warnings
        realP.withUnsafeMutableBufferPointer { realBuffer in
            imagP.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                
                pcmBuffer.withUnsafeBytes { ptr in
                    vDSP_ctoz(ptr.bindMemory(to: DSPComplex.self).baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                
                vDSP_fft_zrip(setup, &splitComplex, 1, vDSP_Length(log2(Float(n))), FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        
        var normalizedMags = [Float](repeating: 0.0, count: halfSize)
        var scalar: Float = 1.0 / (2.0 * Float(n))
        vDSP_vsmul(magnitudes, 1, &scalar, &normalizedMags, 1, vDSP_Length(halfSize))
        
        let minDB: Float = -60.0
        let maxDB: Float = 6.0
        var newAmps = [Float](repeating: 0.0, count: barCount)
        
        let nyquist = sampleRate / 2.0
        let minFreq: Float = 20.0
        let maxFreq: Float = 20000.0
        
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
        
        DispatchQueue.main.async {
            guard AudioPlayerManager.shared.isPlaying else { return }
            
            withAnimation(.linear(duration: 0.08)) {
                self.waveformSamples = currentWaveform
                self.stereoSamples = stereoPts
                for i in 0..<self.barCount {
                    let current = self.amplitudes[i]
                    let new = CGFloat(newAmps[i])
                    // Asymmetric smoothing: fast attack, slow decay (A4)
                    if new > current {
                        self.amplitudes[i] = current * 0.5 + new * 0.5
                    } else {
                        self.amplitudes[i] = current * 0.85 + new * 0.15
                    }
                }
            }
        }
    }
    
    @MainActor
    func reset() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            for i in 0..<barCount {
                self.amplitudes[i] = 0.05
            }
            self.waveformSamples = []
            self.stereoSamples = []
        }
    }
}
