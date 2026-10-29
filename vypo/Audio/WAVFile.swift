import AVFoundation

#if DEBUG
/// Reads and writes recordings as 16 kHz mono Float32 audio files. Debug builds and tests only (Debug menu,
/// benchmark): a Release build has no code that reads or writes audio files.
enum WAVFile {
    static func write(_ samples: [Float], to url: URL) throws {
        let format = AudioRecorder.targetFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        file.close()
    }

    /// Any audio file, converted to 16 kHz mono Float32.
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        // One read may return only part of the file, so read in chunks until the end.
        let block = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        while file.framePosition < file.length {
            try file.read(into: block)
            guard block.frameLength > 0 else { break }
            for ch in 0..<Int(format.channelCount) {
                (inBuf.floatChannelData![ch] + Int(inBuf.frameLength)).update(from: block.floatChannelData![ch], count: Int(block.frameLength))
            }
            inBuf.frameLength += block.frameLength
        }
        let target = AudioRecorder.targetFormat
        if file.processingFormat == target {
            return Array(UnsafeBufferPointer(start: inBuf.floatChannelData![0], count: Int(inBuf.frameLength)))
        }
        let conv = AVAudioConverter(from: file.processingFormat, to: target)!
        let chunk = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16_384)!
        var given = false
        var samples: [Float] = []
        // The converter holds frames back until it has seen the end of the input, so drain it in a loop.
        while true {
            chunk.frameLength = 0
            let status = conv.convert(to: chunk, error: nil) { _, input in
                if given { input.pointee = .endOfStream; return nil }
                given = true
                input.pointee = .haveData
                return inBuf
            }
            samples += UnsafeBufferPointer(start: chunk.floatChannelData![0], count: Int(chunk.frameLength))
            if status == .endOfStream || status == .error || (status == .inputRanDry && chunk.frameLength == 0) { break }
        }
        return samples
    }
}
#endif
