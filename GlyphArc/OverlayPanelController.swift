//
//  OverlayPanelController.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//

import AppKit
import QuartzCore

@MainActor
final class OverlayPanelController {
    private let appState: AppState
    private let motionState = OverlayMotionState()
    private var panel: OverlayPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    private var freezePosition = false
    private lazy var displayLink = DisplayLinkDriver { [weak self] timestamp in
        self?.stepMotion(at: timestamp)
    }

    private var rawTargetOrigin: CGPoint?
    private var smoothedTargetOrigin: CGPoint?
    private var currentOrigin: CGPoint?
    private var velocity = CGVector.zero
    private var lastMotionTime: CFTimeInterval?

    private let instantJumpDistance: CGFloat = 180
    private let staleMotionInterval: CFTimeInterval = 0.12

    init(appState: AppState) {
        self.appState = appState
    }

    func show(near rect: CGRect) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        let wasVisible = panel.isVisible
        let origin = PanelPlacement.controlOrigin(near: rect, size: panel.frame.size)

        panel.orderFrontRegardless()
        move(to: origin, animated: wasVisible)
    }

    func hide() {
        displayLink.stop()
        resetMotion()
        panel?.orderOut(nil)
    }

    func updatePositionIfNeeded(near rect: CGRect) {
        guard let panel, panel.isVisible else { return }
        guard !freezePosition else { return }
        move(to: PanelPlacement.controlOrigin(near: rect, size: panel.frame.size), animated: true)
    }

    func animateTo(size: CGSize, near rect: CGRect, duration: TimeInterval) {
        guard let panel else { return }

        let origin = duration > 0
            ? PanelPlacement.clampedOrigin(panel.frame.origin, size: size, near: rect)
            : PanelPlacement.controlOrigin(near: rect, size: size)
        let newFrame = CGRect(origin: origin, size: size)

        displayLink.stop()
        resetMotion()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }

        currentOrigin = origin
        rawTargetOrigin = origin
        smoothedTargetOrigin = origin
    }

    private func move(to origin: CGPoint, animated: Bool) {
        guard let panel else { return }

        let current = currentOrigin ?? panel.frame.origin
        rawTargetOrigin = origin

        if !animated || shouldSnap(from: current, to: origin) {
            displayLink.stop()
            velocity = .zero
            setPanelOrigin(origin)
            currentOrigin = origin
            smoothedTargetOrigin = origin
            lastMotionTime = nil
            motionState.blurRadius = 0
            return
        }

        if currentOrigin == nil {
            currentOrigin = panel.frame.origin
        }
        if smoothedTargetOrigin == nil {
            smoothedTargetOrigin = currentOrigin
        }

        displayLink.start(window: panel)
    }

    private func shouldSnap(from current: CGPoint, to target: CGPoint) -> Bool {
        let distance = hypot(target.x - current.x, target.y - current.y)
        if distance >= instantJumpDistance { return true }

        guard let lastMotionTime else { return false }
        return CACurrentMediaTime() - lastMotionTime > staleMotionInterval
    }

    private func resetMotion() {
        velocity = .zero
        lastMotionTime = nil
        motionState.blurRadius = 0
    }

    private func stepMotion(at timestamp: CFTimeInterval) {
        guard let panel, let rawTarget = rawTargetOrigin else {
            displayLink.stop()
            resetMotion()
            return
        }

        let previousTime = lastMotionTime ?? timestamp
        let dt = max(1.0 / 240.0, min(timestamp - previousTime, 1.0 / 30.0))
        lastMotionTime = timestamp

        let current = currentOrigin ?? panel.frame.origin
        let targetResponse = CGFloat(1 - exp(-120.0 * dt))
        let target = smoothPoint(
            smoothedTargetOrigin ?? current,
            toward: rawTarget,
            response: targetResponse
        )
        smoothedTargetOrigin = target

        let next = springStep(current: current, target: target, dt: CGFloat(dt))
        let frameDelta = hypot(next.x - current.x, next.y - current.y)

        currentOrigin = next
        setPanelOrigin(next)

        let speed = hypot(velocity.dx, velocity.dy)
        motionState.blurRadius = min(max(frameDelta / 20, speed / 2200), 1.2)

        let remaining = hypot(rawTarget.x - next.x, rawTarget.y - next.y)
        let targetNoise = hypot(rawTarget.x - target.x, rawTarget.y - target.y)
        if remaining < 0.45, targetNoise < 0.45, speed < 3 {
            setPanelOrigin(rawTarget)
            currentOrigin = rawTarget
            smoothedTargetOrigin = rawTarget
            resetMotion()
            displayLink.stop()
        }
    }

    private func smoothPoint(_ current: CGPoint, toward target: CGPoint, response: CGFloat) -> CGPoint {
        CGPoint(
            x: current.x + (target.x - current.x) * response,
            y: current.y + (target.y - current.y) * response
        )
    }

    private func springStep(current: CGPoint, target: CGPoint, dt: CGFloat) -> CGPoint {
        let stiffness: CGFloat = 1_200
        let damping: CGFloat = 68

        let ax = (target.x - current.x) * stiffness - velocity.dx * damping
        let ay = (target.y - current.y) * stiffness - velocity.dy * damping

        velocity.dx += ax * dt
        velocity.dy += ay * dt

        let distance = hypot(target.x - current.x, target.y - current.y)
        let maxStep = max(140, min(520, distance * 1.15))
        var dx = velocity.dx * dt
        var dy = velocity.dy * dt
        let stepLength = hypot(dx, dy)

        if stepLength > maxStep {
            let scale = maxStep / stepLength
            dx *= scale
            dy *= scale
        }

        return CGPoint(x: current.x + dx, y: current.y + dy)
    }

    private func setPanelOrigin(_ origin: CGPoint) {
        guard let panel else { return }
        panel.setFrameOrigin(origin)
    }

    private func createPanel() {
        let p = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true

        let v = HoverMorphMenuView(
            appState: appState,
            motionState: motionState,
            requestResize: { [weak self] size, duration in
                guard let self else { return }
                guard let rect = self.appState.selection?.rect else { return }
                self.animateTo(size: size, near: rect, duration: duration)
            },
            setFreezePosition: { [weak self] freeze in
                self?.freezePosition = freeze
            }
        )

        p.contentView = v
        self.panel = p
    }
}
