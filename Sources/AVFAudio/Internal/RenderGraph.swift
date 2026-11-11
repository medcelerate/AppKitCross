// The compiled render graph: what the render thread walks every cycle. Built on the
// control thread from the engine's connection tables (allocating freely); `render` then
// runs without allocating, locking or touching anything the control thread mutates.

import Foundation

final class _RenderNode {
    let node: AVAudioNode
    let channels: Int
    let rate: Double
    let capacity: Int
    /// Planar scratch output of bus 0 for the current cycle.
    let out: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    var inputs: [_RenderInput] = []
    var taps: [_TapState] = []
    /// Cycle number of the last render, so fan-out pulls reuse the output.
    var renderedCycle: Int64 = -1
    var renderedFrames = 0
    var renderedHasAudio = false
    let kind: Kind
    enum Kind {
        case player(_PlayerRenderState), mixer(AVAudioMixerNode), output, effect(_EffectState)
        case timeEffect(_TimeEffectState), source(_SourceRenderState), input(AVAudioInputNode, _InputCapture?), sink(_SinkRenderState)
    }

    init(node: AVAudioNode, format: AVAudioFormat, capacity: Int, kind: Kind) {
        self.node = node
        channels = max(1, Int(format.channelCount))
        rate = format.sampleRate
        self.capacity = capacity
        self.kind = kind
        out = .allocate(capacity: channels)
        for c in 0..<channels { out[c] = .allocate(capacity: capacity); out[c].initialize(repeating: 0, count: capacity) }
    }

    deinit {
        for c in 0..<channels { out[c].deallocate() }
        out.deallocate()
    }
}

/// A connected input bus: where the frames come from and how they are adapted.
final class _RenderInput {
    let source: _RenderNode
    let bus: Int
    let converter: _RateConverter?
    /// Scratch for the converter's output (source channel count).
    let converted: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    let mixing: _MixingParameters?
    /// For a mixer input whose channel count has no direct law (not mono/stereo into
    /// stereo, not anything into mono): AVAudioConverter's downmix matrix, and its scratch.
    let matrix: _ChannelMatrix?
    let mapped: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    let mappedChannels: Int
    init(source: _RenderNode, bus: Int, converter: _RateConverter?, capacity: Int, mixing: _MixingParameters?, destinationChannels: Int = 0) {
        self.source = source; self.bus = bus; self.converter = converter; self.mixing = mixing
        let i = source.channels, o = destinationChannels
        if mixing != nil && o > 0 && i != o && o != 1 && !(o == 2 && i == 1) {
            let m = i > o ? _ChannelMatrix.downmix(inputs: i, outputs: o) : _ChannelMatrix.standard(inputs: i, outputs: o)
            matrix = m
            let p = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: o)
            for c in 0..<o { p[c] = .allocate(capacity: capacity); p[c].initialize(repeating: 0, count: capacity) }
            mapped = p
            mappedChannels = o
        } else {
            matrix = nil; mapped = nil; mappedChannels = 0
        }
        if converter != nil {
            let p = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: source.channels)
            for c in 0..<source.channels { p[c] = .allocate(capacity: capacity); p[c].initialize(repeating: 0, count: capacity) }
            converted = p
        } else {
            converted = nil
        }
    }
    deinit {
        if let converted { for c in 0..<source.channels { converted[c].deallocate() }; converted.deallocate() }
        if let mapped { for c in 0..<mappedChannels { mapped[c].deallocate() }; mapped.deallocate() }
    }
}

/// Per-channel processing state of an effect node (the EQ).
protocol _EffectState: AnyObject {
    /// Processes `frames` frames in place.
    func process(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames: Int, rate: Double)
}

final class _RenderGraph {
    let maxFrames: Int
    let rate: Double
    let channels: Int
    let latencyFrames: Int64
    private(set) var nodes: [_RenderNode] = []
    let output: _RenderNode
    /// Nodes pulled every cycle besides the output's chain: sink nodes, and the input node
    /// when only a tap uses it. Each keeps the fraction of a frame it is owed when its rate
    /// differs from the graph's.
    private var extras: [_RenderNode] = []
    private var extraFractions: [Double] = []
    private var cycle: Int64 = 0
    /// Scratch for the interleaved/planar output conversion.
    private let outputPlanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    init(engine: AVAudioEngine, outputNode: AVAudioOutputNode, format: AVAudioFormat, maxFrames: Int, latencyFrames: Int64, manualRendering: Bool) {
        self.maxFrames = maxFrames
        rate = format.sampleRate
        channels = max(1, Int(format.channelCount))
        self.latencyFrames = latencyFrames
        // A source feeding a converter is pulled for up to ratio * frames; 8x covers 192 kHz
        // into 24 kHz, the widest ratio the converter accepts.
        let capacity = maxFrames * 8 + 256
        output = _RenderNode(node: outputNode, format: format, capacity: capacity, kind: .output)
        outputPlanes = .allocate(capacity: channels)
        for c in 0..<channels { outputPlanes[c] = .allocate(capacity: maxFrames); outputPlanes[c].initialize(repeating: 0, count: maxFrames) }
        var built: [ObjectIdentifier: _RenderNode] = [ObjectIdentifier(outputNode): output]
        var order: [_RenderNode] = []

        func build(_ node: AVAudioNode, format: AVAudioFormat) -> _RenderNode {
            if let existing = built[ObjectIdentifier(node)] { return existing }
            let kind: _RenderNode.Kind
            switch node {
            case let p as AVAudioPlayerNode: kind = .player(p._state)
            case let m as AVAudioMixerNode: kind = .mixer(m)
            case let e as AVAudioUnitEffect: kind = .effect(e._makeEffectState(channels: Int(format.channelCount), rate: format.sampleRate))
            case let t as AVAudioUnitTimeEffect: kind = .timeEffect(t._makeTimeEffectState(channels: max(1, Int(format.channelCount)), rate: format.sampleRate, maxFrames: maxFrames))
            case let s as AVAudioSourceNode: kind = .source(_SourceRenderState(node: s, connectionFormat: format, maxFrames: capacity))
            case let i as AVAudioInputNode: kind = .input(i, manualRendering ? nil : i._capture)
            case let k as AVAudioSinkNode: kind = .sink(_SinkRenderState(node: k, channels: max(1, Int(format.channelCount))))
            default: kind = .output
            }
            let r = _RenderNode(node: node, format: format, capacity: capacity, kind: kind)
            built[ObjectIdentifier(node)] = r
            wire(r)
            order.append(r)
            return r
        }

        func wire(_ r: _RenderNode) {
            let connections = r.node._inputConnections.sorted { $0.key < $1.key }
            for (bus, connection) in connections {
                let src = build(connection.source, format: connection.format)
                let needsConversion = src.rate != r.rate
                let converter = needsConversion ? _RateConverter(channels: src.channels, inputRate: src.rate, outputRate: r.rate, maxOutputFrames: maxFrames) : nil
                var mixing: _MixingParameters? = nil
                if r.node is AVAudioMixerNode {
                    switch connection.source {
                    case let p as AVAudioPlayerNode: mixing = p._mixingSource.parameters(forMixer: r.node, bus: bus)
                    case let m as AVAudioMixerNode: mixing = m._mixingSource.parameters(forMixer: r.node, bus: bus)
                    case let i as AVAudioInputNode: mixing = i._mixingSource.parameters(forMixer: r.node, bus: bus)
                    case let s as AVAudioSourceNode: mixing = s._mixingSource.parameters(forMixer: r.node, bus: bus)
                    default: mixing = nil
                    }
                }
                r.inputs.append(_RenderInput(source: src, bus: bus, converter: converter, capacity: maxFrames, mixing: mixing, destinationChannels: r.channels))
            }
            // Taps deliver only when a device renders; Apple's do not fire in manual
            // rendering mode either.
            r.taps = manualRendering ? [] : r.node._taps.values.filter { $0.bus == 0 }
        }

        wire(output)
        order.append(output)
        // Sinks have no output to be pulled through; the input node feeds taps even when
        // nothing downstream renders it.
        for node in engine._attachedNodesLocked() {
            guard built[ObjectIdentifier(node)] == nil else { continue }
            if node is AVAudioSinkNode, let c = node._inputConnections[0] {
                extras.append(build(node, format: c.format))
            } else if let input = node as? AVAudioInputNode, !input._taps.isEmpty, !manualRendering {
                extras.append(build(input, format: input.outputFormat(forBus: 0)))
            }
        }
        extraFractions = Array(repeating: 0, count: extras.count)
        nodes = order
        for n in nodes {
            n.node._lastRate.value = n.rate
            n.node._presentationLatency.value = latencyFrames < 0 ? 0 : Double(latencyFrames) / format.sampleRate
        }
    }

    deinit {
        for c in 0..<channels { outputPlanes[c].deallocate() }
        outputPlanes.deallocate()
    }

    // MARK: Render thread

    /// Renders `frames` frames of the output node into interleaved Float32.
    func render(frames: Int, sampleTime: Int64, hostTime: Int64, into interleaved: UnsafeMutablePointer<Float>) {
        let n = min(frames, maxFrames)
        renderPlanar(frames: n, sampleTime: sampleTime, hostTime: hostTime)
        for c in 0..<channels {
            let src = outputPlanes[c]
            var i = c
            for f in 0..<n { interleaved[i] = src[f]; i += channels }
        }
        if frames > n { (interleaved + n * channels).update(repeating: 0, count: (frames - n) * channels) }
    }

    /// Renders into the planar scratch (`planes`).
    @discardableResult
    func renderPlanar(frames: Int, sampleTime: Int64, hostTime: Int64) -> Bool {
        cycle += 1
        let hasAudio = pull(output, frames: frames, sampleTime: sampleTime, hostTime: hostTime)
        for c in 0..<channels { outputPlanes[c].update(from: output.out[c], count: frames) }
        for i in 0..<extras.count {
            let x = extras[i]
            var n = frames
            if x.rate != rate {
                let exact = Double(frames) * x.rate / rate + extraFractions[i]
                n = Int(exact.rounded(.down))
                extraFractions[i] = exact - Double(n)
            }
            n = min(n, maxFrames)
            if n > 0 { _ = pull(x, frames: n, sampleTime: Int64(Double(sampleTime) * x.rate / rate), hostTime: hostTime) }
        }
        return hasAudio
    }

    var planes: UnsafePointer<UnsafeMutablePointer<Float>> { UnsafePointer(outputPlanes) }

    /// Renders `r` for this cycle (once; later pulls reuse the output). Returns whether the
    /// output has audio (false: it is zeros).
    private func pull(_ r: _RenderNode, frames: Int, sampleTime: Int64, hostTime: Int64) -> Bool {
        if r.renderedCycle == cycle {
            if r.renderedFrames < frames { for c in 0..<r.channels { (r.out[c] + r.renderedFrames).update(repeating: 0, count: frames - r.renderedFrames) } }
            return r.renderedHasAudio
        }
        r.renderedCycle = cycle
        r.renderedFrames = frames
        let n = min(frames, r.capacity)
        var hasAudio = false
        switch r.kind {
        case .player(let state):
            hasAudio = state.render(into: UnsafePointer(r.out), channels: r.channels, frames: n, nodeSampleTime: sampleTime, latencyFrames: latencyFrames)
            if !state.completions.isEmpty { _DeliveryHub.shared.signal() }
        case .mixer(let mixer):
            for c in 0..<r.channels { r.out[c].update(repeating: 0, count: n) }
            for input in r.inputs {
                guard let planes = pullAdapted(input, frames: n, sampleTime: sampleTime, hostTime: hostTime) else { continue }
                let volume = input.mixing?.volume.value ?? 1
                let pan = input.mixing?.pan.value ?? 0
                if let matrix = input.matrix, let mapped = input.mapped {
                    matrix.apply(planes, into: UnsafePointer(mapped), frames: n)
                    mix(UnsafePointer(mapped), inChannels: r.channels, into: r.out, outChannels: r.channels, frames: n, volume: volume, pan: pan)
                } else {
                    mix(planes, inChannels: input.source.channels, into: r.out, outChannels: r.channels, frames: n, volume: volume, pan: pan)
                }
                hasAudio = true
            }
            let gain = mixer._outputVolume.value
            if gain != 1 { for c in 0..<r.channels { let p = r.out[c]; for i in 0..<n { p[i] *= gain } } }
        case .timeEffect(let state):
            if state.isBypassed {
                if let input = r.inputs.first, let planes = pullAdapted(input, frames: n, sampleTime: state.inputSampleTime, hostTime: hostTime) {
                    copyChannels(planes, inChannels: input.source.channels, into: r.out, outChannels: r.channels, frames: n)
                    hasAudio = true
                } else {
                    for c in 0..<r.channels { r.out[c].update(repeating: 0, count: n) }
                }
                state.inputSampleTime += Int64(n)
            } else if let input = r.inputs.first {
                // Pull what the unit asks for, in pieces no larger than the source's
                // scratch; a further piece is a new pass over the upstream nodes.
                var pieces = 0
                while pieces < 4096 {
                    let want = state.inputFramesWanted(forOutput: n)
                    if want <= 0 { break }
                    let take = min(want, input.source.capacity, maxFrames)
                    if pieces > 0 { cycle += 1 }
                    if let planes = pullAdapted(input, frames: take, sampleTime: state.inputSampleTime, hostTime: hostTime) {
                        if input.source.channels == r.channels { state.push(planes, frames: take) }
                        else { copyChannels(planes, inChannels: input.source.channels, into: r.out, outChannels: r.channels, frames: take); state.push(UnsafePointer(r.out), frames: take) }
                    } else {
                        for c in 0..<r.channels { r.out[c].update(repeating: 0, count: take) }
                        state.push(UnsafePointer(r.out), frames: take)
                    }
                    state.inputSampleTime += Int64(take)
                    pieces += 1
                }
                r.renderedCycle = cycle
                state.produce(UnsafePointer(r.out), frames: n)
                hasAudio = true
            } else {
                for c in 0..<r.channels { r.out[c].update(repeating: 0, count: n) }
            }
        case .source(let state):
            hasAudio = state.render(into: UnsafePointer(r.out), frames: n, sampleTime: sampleTime, hostTime: hostTime)
        case .input(let node, let capture):
            hasAudio = node._renderInput(into: UnsafePointer(r.out), channels: r.channels, frames: n, capture: capture)
        case .sink(let state):
            if let input = r.inputs.first, let planes = pullAdapted(input, frames: n, sampleTime: sampleTime, hostTime: hostTime) {
                copyChannels(planes, inChannels: input.source.channels, into: r.out, outChannels: r.channels, frames: n)
                hasAudio = true
            } else {
                for c in 0..<r.channels { r.out[c].update(repeating: 0, count: n) }
            }
            state.deliver(UnsafePointer(r.out), frames: n, sampleTime: sampleTime, hostTime: hostTime)
        case .output, .effect:
            if let input = r.inputs.first, let planes = pullAdapted(input, frames: n, sampleTime: sampleTime, hostTime: hostTime) {
                copyChannels(planes, inChannels: input.source.channels, into: r.out, outChannels: r.channels, frames: n)
                hasAudio = true
            } else {
                for c in 0..<r.channels { r.out[c].update(repeating: 0, count: n) }
            }
            if case .effect(let state) = r.kind, hasAudio {
                state.process(UnsafePointer(r.out), channels: r.channels, frames: n, rate: r.rate)
            }
        }
        r.renderedHasAudio = hasAudio
        r.node._lastSampleTime.value = sampleTime
        r.node._lastHostTime.value = hostTime
        for tap in r.taps { tap.push(UnsafePointer(r.out), frames: n, sampleTime: sampleTime, hostTime: hostTime) }
        if !r.taps.isEmpty { _DeliveryHub.shared.signal() }
        return hasAudio
    }

    /// Pulls an input at the destination's rate; nil when the source is silent.
    private func pullAdapted(_ input: _RenderInput, frames: Int, sampleTime: Int64, hostTime: Int64) -> UnsafePointer<UnsafeMutablePointer<Float>>? {
        guard let converter = input.converter, let converted = input.converted else {
            let has = pull(input.source, frames: frames, sampleTime: sampleTime, hostTime: hostTime)
            return has ? UnsafePointer(input.source.out) : nil
        }
        let need = converter.inputFramesNeeded(for: frames)
        var has = false
        if need > 0 {
            // Source time advances at its own rate: scale the node time for its clock.
            let srcTime = Int64(Double(sampleTime) * input.source.rate / rate)
            has = pull(input.source, frames: min(need, input.source.capacity), sampleTime: srcTime, hostTime: hostTime)
            converter.push(UnsafePointer(input.source.out), frames: min(need, input.source.capacity))
        }
        converter.produce(UnsafePointer(converted), frames: frames)
        return has || input.source.renderedHasAudio ? UnsafePointer(converted) : UnsafePointer(converted)
    }

    /// Apple's laws: stereo pan is a linear balance; mono into stereo is unity at pan 0 and
    /// constant-power (cos/sin) otherwise; other channel counts map one to one.
    private func mix(_ src: UnsafePointer<UnsafeMutablePointer<Float>>, inChannels: Int, into dst: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, outChannels: Int, frames: Int, volume: Float, pan: Float) {
        let p = max(-1, min(1, pan))
        if inChannels == 1 && outChannels == 2 {
            let l: Float, r: Float
            if p == 0 { l = 1; r = 1 } else {
                let a = (Double(p) + 1) * Double.pi / 4
                l = Float(cos(a)); r = Float(sin(a))
            }
            let s = src[0], dl = dst[0], dr = dst[1]
            let gl = volume * l, gr = volume * r
            for i in 0..<frames { dl[i] += s[i] * gl; dr[i] += s[i] * gr }
            return
        }
        if inChannels == 2 && outChannels == 2 {
            let gl = volume * min(1, 1 - p), gr = volume * min(1, 1 + p)
            let sl = src[0], sr = src[1], dl = dst[0], dr = dst[1]
            for i in 0..<frames { dl[i] += sl[i] * gl; dr[i] += sr[i] * gr }
            return
        }
        if outChannels == 1 {
            let d = dst[0]
            let g = volume / Float(inChannels)
            for c in 0..<inChannels { let s = src[c]; for i in 0..<frames { d[i] += s[i] * g } }
            return
        }
        for c in 0..<outChannels {
            let s = src[inChannels == 1 ? 0 : min(c, inChannels - 1)]
            if c >= inChannels && inChannels != 1 { continue }
            let d = dst[c]
            for i in 0..<frames { d[i] += s[i] * volume }
        }
    }

    private func copyChannels(_ src: UnsafePointer<UnsafeMutablePointer<Float>>, inChannels: Int, into dst: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, outChannels: Int, frames: Int) {
        if inChannels == outChannels {
            for c in 0..<outChannels { dst[c].update(from: src[c], count: frames) }
        } else if inChannels == 1 {
            for c in 0..<outChannels { dst[c].update(from: src[0], count: frames) }
        } else if outChannels == 1 {
            let d = dst[0]
            d.update(repeating: 0, count: frames)
            let g = 1 / Float(inChannels)
            for c in 0..<inChannels { let s = src[c]; for i in 0..<frames { d[i] += s[i] * g } }
        } else {
            for c in 0..<outChannels {
                if c < inChannels { dst[c].update(from: src[c], count: frames) } else { dst[c].update(repeating: 0, count: frames) }
            }
        }
    }
}
