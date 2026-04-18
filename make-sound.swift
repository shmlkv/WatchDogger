import AVFoundation
import Foundation

let sampleRate: Double = 44100
let duration: Double = 0.25
let frameCount = Int(sampleRate * duration)
var samples = [Float](repeating: 0, count: frameCount)

// Single deep "boop" — 280Hz with soft attack and decay
for i in 0..<frameCount {
    let t = Double(i) / sampleRate
    // Fast attack (5ms), smooth decay
    let attack = min(1.0, t / 0.005)
    let decay = max(0, 1.0 - t / duration)
    let envelope = attack * decay * decay  // quadratic decay for warmth
    // Mix fundamental + subtle octave for richness
    let fundamental = sin(2.0 * .pi * 280 * t)
    let octave = sin(2.0 * .pi * 560 * t) * 0.2
    samples[i] = Float((fundamental + octave) * envelope * 0.8)
}

let outputPath = "WatchDogger.app/Contents/Resources/alert.aiff"
let url = URL(fileURLWithPath: outputPath)
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
buffer.frameLength = AVAudioFrameCount(frameCount)
let channelData = buffer.floatChannelData![0]
for i in 0..<frameCount { channelData[i] = samples[i] }

do {
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    print("OK")
} catch { print("Error: \(error)") }
