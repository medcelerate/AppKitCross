// A radix-2 complex FFT over split real/imaginary arrays, and a real FFT of twice its size
// built on it (the usual packing of even and odd samples into one complex sequence).
// Tables are built on construction; `forward`/`inverse` neither allocate nor lock, so the
// phase vocoder can run them on the render thread.

import Foundation

final class _FFT {
    /// Real transform size (a power of two, at least 8).
    let size: Int
    private let half: Int
    private let log2Half: Int
    private let bitReverse: UnsafeMutablePointer<Int32>
    private let cosTable: UnsafeMutablePointer<Float>     // e^{-2 pi i k / half}, k < half/2
    private let sinTable: UnsafeMutablePointer<Float>
    private let postCos: UnsafeMutablePointer<Float>      // e^{-2 pi i k / size}, k < half
    private let postSin: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>
    private let im: UnsafeMutablePointer<Float>

    init(size: Int) {
        precondition(size >= 8 && size & (size - 1) == 0, "_FFT: the size must be a power of two")
        self.size = size
        half = size / 2
        var l = 0
        while (1 << l) < half { l += 1 }
        log2Half = l
        bitReverse = .allocate(capacity: half)
        for i in 0..<half {
            var r = 0, x = i
            for _ in 0..<l { r = (r << 1) | (x & 1); x >>= 1 }
            bitReverse[i] = Int32(r)
        }
        cosTable = .allocate(capacity: max(1, half / 2))
        sinTable = .allocate(capacity: max(1, half / 2))
        for k in 0..<max(1, half / 2) {
            let a = -2 * Double.pi * Double(k) / Double(half)
            cosTable[k] = Float(cos(a)); sinTable[k] = Float(sin(a))
        }
        postCos = .allocate(capacity: half)
        postSin = .allocate(capacity: half)
        for k in 0..<half {
            let a = -2 * Double.pi * Double(k) / Double(size)
            postCos[k] = Float(cos(a)); postSin[k] = Float(sin(a))
        }
        re = .allocate(capacity: half); re.initialize(repeating: 0, count: half)
        im = .allocate(capacity: half); im.initialize(repeating: 0, count: half)
    }

    deinit {
        bitReverse.deallocate(); cosTable.deallocate(); sinTable.deallocate()
        postCos.deallocate(); postSin.deallocate(); re.deallocate(); im.deallocate()
    }

    /// In-place complex FFT of `half` points (sign -1 forward, +1 inverse, unscaled).
    private func complexFFT(_ xr: UnsafeMutablePointer<Float>, _ xi: UnsafeMutablePointer<Float>, inverse: Bool) {
        let n = half
        for i in 0..<n {
            let j = Int(bitReverse[i])
            if j > i {
                let tr = xr[i]; xr[i] = xr[j]; xr[j] = tr
                let ti = xi[i]; xi[i] = xi[j]; xi[j] = ti
            }
        }
        let sign: Float = inverse ? -1 : 1
        var len = 2
        while len <= n {
            let halfLen = len / 2
            let step = n / len
            var start = 0
            while start < n {
                var k = 0
                for j in 0..<halfLen {
                    let wr = cosTable[k], wi = sign * sinTable[k]
                    let a = start + j, b = a + halfLen
                    let br = xr[b] * wr - xi[b] * wi
                    let bi = xr[b] * wi + xi[b] * wr
                    xr[b] = xr[a] - br; xi[b] = xi[a] - bi
                    xr[a] += br; xi[a] += bi
                    k += step
                }
                start += len
            }
            len <<= 1
        }
    }

    /// The spectrum of `size` real samples: bins 0...size/2 into `outRe`/`outIm`
    /// (`size/2 + 1` entries each).
    func forward(_ input: UnsafePointer<Float>, re outRe: UnsafeMutablePointer<Float>, im outIm: UnsafeMutablePointer<Float>) {
        for i in 0..<half { re[i] = input[2 * i]; im[i] = input[2 * i + 1] }
        complexFFT(re, im, inverse: false)
        // Split the packed transform into the even and odd halves and combine.
        outRe[0] = re[0] + im[0]; outIm[0] = 0
        outRe[half] = re[0] - im[0]; outIm[half] = 0
        for k in 1..<half {
            let ar = re[k], ai = im[k], br = re[half - k], bi = -im[half - k]
            let er = 0.5 * (ar + br), ei = 0.5 * (ai + bi)          // even part
            let or = 0.5 * (ai - bi), oi = -0.5 * (ar - br)          // odd part (times -i)
            let wr = postCos[k], wi = postSin[k]
            outRe[k] = er + or * wr - oi * wi
            outIm[k] = ei + or * wi + oi * wr
        }
    }

    /// The inverse of `forward`, scaled so that inverse(forward(x)) == x.
    func inverse(re inRe: UnsafePointer<Float>, im inIm: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>) {
        for k in 0..<half {
            let xr = inRe[k], xi = inIm[k], yr = inRe[half - k], yi = -inIm[half - k]
            let er = xr + yr, ei = xi + yi                          // 2 * even
            let dr = xr - yr, di = xi - yi                          // 2 * odd * w
            let wr = postCos[k], wi = -postSin[k]                   // conj(w)
            let or = dr * wr - di * wi, oi = dr * wi + di * wr
            re[k] = er - oi; im[k] = ei + or                        // even + i * odd
        }
        complexFFT(re, im, inverse: true)
        let scale = 1 / Float(size)
        for i in 0..<half { output[2 * i] = re[i] * scale; output[2 * i + 1] = im[i] * scale }
    }
}
