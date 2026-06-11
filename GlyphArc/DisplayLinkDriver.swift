//
//  DisplayLinkDriver.swift
//  GlyphArc
//

import AppKit
import QuartzCore

@MainActor
final class DisplayLinkDriver: NSObject {
    private var displayLink: CADisplayLink?
    private let onFrame: (CFTimeInterval) -> Void

    init(onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func start(window: NSWindow?) {
        guard displayLink == nil else { return }
        guard let link = window?.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            ?? NSScreen.main?.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        else {
            return
        }

        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        guard let displayLink else { return }
        displayLink.invalidate()
        self.displayLink = nil
    }

    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        onFrame(displayLink.timestamp)
    }
}
