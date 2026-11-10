//
//  Portability.swift
//  Combine (ported from OpenCombine)
//
//  Created by Sergej Jaskiewicz on 28.10.2020.
//
//  AppKitCross: upstream switches between CFRunLoopTimer on Darwin and Foundation.Timer
//  on swift-corelibs-foundation. This module is only built against corelibs (Windows
//  and Linux), so only that branch is kept, and the wrapper is named `PortableTimer`
//  so it cannot be confused with `Foundation.Timer` inside `extension Timer`.

import Foundation

internal struct PortableTimer {

    fileprivate let underlyingTimer: Foundation.Timer

    private init(underlyingTimer: Foundation.Timer) {
        self.underlyingTimer = underlyingTimer
    }

    internal init(fire date: Date,
                  interval: TimeInterval,
                  repeats: Bool,
                  block: @escaping (PortableTimer) -> Void) {
        underlyingTimer = Foundation.Timer(
            fire: date,
            interval: interval,
            repeats: repeats,
            block: { block(PortableTimer(underlyingTimer: $0)) }
        )
    }

    internal init(
        timeInterval: TimeInterval,
        repeats: Bool,
        block: @escaping (PortableTimer) -> Void
    ) {
        self.init(
            fire: Date() + timeInterval,
            interval: timeInterval,
            repeats: repeats,
            block: block
        )
    }

    internal var tolerance: TimeInterval {
        get { return underlyingTimer.tolerance }
        nonmutating set { underlyingTimer.tolerance = newValue }
    }

    internal func invalidate() {
        underlyingTimer.invalidate()
    }
}

extension RunLoop {
    internal func add(_ timer: PortableTimer, forMode mode: RunLoop.Mode) {
        add(timer.underlyingTimer, forMode: mode)
    }

    internal func performBlockPortably(_ block: @escaping () -> Void) {
        perform(block)
    }
}
