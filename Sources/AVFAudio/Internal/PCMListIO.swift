// Sample access to an AudioBufferList in any of the common PCM formats, reading the data
// pointers from the list each time (a source node's render block may replace them), plus
// the channel mapping shared by AVAudioConverter, the mixer and the input chain. No
// allocation: the render thread uses these.

import Foundation

enum _PCMListIO {
    /// Converts `count` frames from `frame` of `channel` into Float32 (`out`).
    static func read(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat, channel: Int, frame: Int, count: Int, into out: UnsafeMutablePointer<Float>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let interleaved = format.isInterleaved
        let channels = Int(format.channelCount)
        let bufferIndex = interleaved ? 0 : channel
        guard bufferIndex < abl.count, let data = abl[bufferIndex].mData else { out.update(repeating: 0, count: count); return }
        let stride = interleaved ? channels : 1
        let first = interleaved ? channel : 0
        switch format.commonFormat {
        case .pcmFormatFloat32:
            let p = data.assumingMemoryBound(to: Float.self) + first
            if stride == 1 { out.update(from: p + frame, count: count) } else { for i in 0..<count { out[i] = p[(frame + i) * stride] } }
        case .pcmFormatInt16:
            let p = data.assumingMemoryBound(to: Int16.self) + first
            for i in 0..<count { out[i] = Float(p[(frame + i) * stride]) * (1.0 / 32768) }
        case .pcmFormatInt32:
            let p = data.assumingMemoryBound(to: Int32.self) + first
            for i in 0..<count { out[i] = Float(Double(p[(frame + i) * stride]) / 2147483648) }
        case .pcmFormatFloat64:
            let p = data.assumingMemoryBound(to: Double.self) + first
            for i in 0..<count { out[i] = Float(p[(frame + i) * stride]) }
        case .otherFormat:
            out.update(repeating: 0, count: count)
        }
    }

    /// Writes Float32 samples into `channel` from `frame`, converting to the format
    /// (integers round and clip).
    static func write(_ list: UnsafeMutablePointer<AudioBufferList>, format: AVAudioFormat, channel: Int, frame: Int, count: Int, from src: UnsafePointer<Float>) {
        let abl = UnsafeMutableAudioBufferListPointer(list)
        let interleaved = format.isInterleaved
        let channels = Int(format.channelCount)
        let bufferIndex = interleaved ? 0 : channel
        guard bufferIndex < abl.count, let data = abl[bufferIndex].mData else { return }
        let stride = interleaved ? channels : 1
        let first = interleaved ? channel : 0
        switch format.commonFormat {
        case .pcmFormatFloat32:
            let p = data.assumingMemoryBound(to: Float.self) + first
            if stride == 1 { (p + frame).update(from: src, count: count) } else { for i in 0..<count { p[(frame + i) * stride] = src[i] } }
        case .pcmFormatInt16:
            let p = data.assumingMemoryBound(to: Int16.self) + first
            for i in 0..<count { p[(frame + i) * stride] = _floatToInt16(src[i]) }
        case .pcmFormatInt32:
            let p = data.assumingMemoryBound(to: Int32.self) + first
            for i in 0..<count { p[(frame + i) * stride] = _floatToInt32(src[i]) }
        case .pcmFormatFloat64:
            let p = data.assumingMemoryBound(to: Double.self) + first
            for i in 0..<count { p[(frame + i) * stride] = Double(src[i]) }
        case .otherFormat: break
        }
    }

    /// Points a list allocated for `format` at `frames` frames of `storage` planes (or one
    /// interleaved plane) and sets the byte sizes.
    static func setSizes(_ list: UnsafeMutablePointer<AudioBufferList>, format: AVAudioFormat, frames: Int) {
        let abl = UnsafeMutableAudioBufferListPointer(list)
        let bytes = UInt32(frames * Int(format.streamDescription.pointee.mBytesPerFrame))
        for b in 0..<abl.count { abl[b].mDataByteSize = bytes }
    }
}

/// How output channels are derived from input channels: a matrix of gains, built once
/// (`channelMap` semantics, Apple's default mono-to-many duplication, or a downmix).
struct _ChannelMatrix {
    let inputs: Int
    let outputs: Int
    /// gains[out * inputs + in]
    var gains: [Float]

    /// The default mapping (no downmix): channel n to channel n, mono duplicated into every
    /// output, extra outputs silent and extra inputs dropped.
    static func standard(inputs: Int, outputs: Int) -> _ChannelMatrix {
        var g = [Float](repeating: 0, count: inputs * outputs)
        for o in 0..<outputs {
            if inputs == 1 { g[o * inputs] = 1 }
            else if o < inputs { g[o * inputs + o] = 1 }
        }
        return _ChannelMatrix(inputs: inputs, outputs: outputs, gains: g)
    }

    /// From AVAudioConverter.channelMap: output n copies input map[n] (negative: silent).
    static func map(_ map: [Int], inputs: Int, outputs: Int) -> _ChannelMatrix {
        var g = [Float](repeating: 0, count: inputs * outputs)
        for o in 0..<outputs where o < map.count && map[o] >= 0 && map[o] < inputs { g[o * inputs + map[o]] = 1 }
        return _ChannelMatrix(inputs: inputs, outputs: outputs, gains: g)
    }

    /// A downmix: every input folds into the outputs. Stereo to mono averages; more
    /// channels into stereo use the ITU-R BS.775 coefficients for the 5.1 order (L R C
    /// LFE Ls Rs, LFE dropped, centre and surrounds at -3 dB), normalized so a full-scale
    /// signal on every input stays at full scale.
    static func downmix(inputs: Int, outputs: Int) -> _ChannelMatrix {
        var g = [Float](repeating: 0, count: inputs * outputs)
        if outputs == 1 {
            for i in 0..<inputs { g[i] = 1 / Float(inputs) }
        } else if outputs == 2 && inputs > 2 {
            let m: Float = 0.70710678
            var left = [Float](repeating: 0, count: inputs), right = left
            for i in 0..<inputs {
                switch i {
                case 0: left[i] = 1
                case 1: right[i] = 1
                case 2: left[i] = m; right[i] = m
                case 3: break                                   // LFE
                default: if i % 2 == 0 { left[i] = m } else { right[i] = m }
                }
            }
            let sum = max(left.reduce(0, +), right.reduce(0, +))
            for i in 0..<inputs { g[i] = left[i] / sum; g[inputs + i] = right[i] / sum }
        } else {
            return standard(inputs: inputs, outputs: outputs)
        }
        return _ChannelMatrix(inputs: inputs, outputs: outputs, gains: g)
    }

    /// Applies the matrix to planar input (`inputs` lanes) into planar output.
    func apply(_ src: UnsafePointer<UnsafeMutablePointer<Float>>, into dst: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        gains.withUnsafeBufferPointer { g in
            for o in 0..<outputs {
                let d = dst[o]
                var first = true
                for i in 0..<inputs {
                    let gain = g[o * inputs + i]
                    if gain == 0 { continue }
                    let s = src[i]
                    if first {
                        if gain == 1 { d.update(from: s, count: frames) } else { for f in 0..<frames { d[f] = s[f] * gain } }
                        first = false
                    } else {
                        for f in 0..<frames { d[f] += s[f] * gain }
                    }
                }
                if first { d.update(repeating: 0, count: frames) }
            }
        }
    }
}
