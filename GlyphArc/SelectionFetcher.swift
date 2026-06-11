//
//  SelectionFetcher.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//

import Foundation
import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices

struct SelectionScreenSnapshot: Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
    let cgBounds: CGRect?
    let isMain: Bool
}

struct SelectionFetchContext: Sendable {
    let processIdentifier: pid_t
    let bundleID: String?
    let screens: [SelectionScreenSnapshot]
    let mouseLocation: CGPoint

    var mainScreen: SelectionScreenSnapshot? {
        screens.first(where: \.isMain) ?? screens.first
    }

    @MainActor
    static func current() -> SelectionFetchContext? {
        // Если Accessibility не выдан — AX вызовы бессмысленны.
        guard AXIsProcessTrusted() else { return nil }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }

        let mainFrame = NSScreen.main?.frame
        let screens = NSScreen.screens.map { screen in
            let displayID = screen.displayID
            return SelectionScreenSnapshot(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                cgBounds: displayID.map { CGDisplayBounds($0) },
                isMain: mainFrame.map { screen.frame == $0 } ?? false
            )
        }

        return SelectionFetchContext(
            processIdentifier: frontmost.processIdentifier,
            bundleID: frontmost.bundleIdentifier,
            screens: screens,
            mouseLocation: NSEvent.mouseLocation
        )
    }
}

final class SelectionFetcher {
    private let axSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
    private let axBoundsForTextMarkerRangeParameterizedAttribute = "AXBoundsForTextMarkerRange" as CFString
    private let axStringForTextMarkerRangeParameterizedAttribute = "AXStringForTextMarkerRange" as CFString

    private var lastRectPoints: CGRect?
    private var lastElement: AXUIElement?
    private var lastProcessIdentifier: pid_t?
    private let maxSearchDepth = 7
    private let maxSearchNodes = 180

    func fetch(context: SelectionFetchContext) -> SelectionSnapshot? {
        resetCacheIfNeeded(for: context)

        let appElement = AXUIElementCreateApplication(context.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()

        if let lastElement,
           let snap = snapshot(from: lastElement, context: context) {
            return snap
        }

        var roots: [AXUIElement] = []
        var seenRoots = Set<CFHashCode>()

        appendUnique(copyElement(systemWide, kAXFocusedUIElementAttribute as CFString), to: &roots, seen: &seenRoots)
        appendUnique(copyElement(appElement, kAXFocusedUIElementAttribute as CFString), to: &roots, seen: &seenRoots)
        appendUnique(copyElement(appElement, kAXFocusedWindowAttribute as CFString), to: &roots, seen: &seenRoots)

        for root in roots {
            for child in copyElementArray(root, kAXSelectedChildrenAttribute as CFString) {
                appendUnique(child, to: &roots, seen: &seenRoots)
            }
        }

        for root in roots {
            if let snap = snapshot(from: root, context: context) {
                return snap
            }
        }

        for root in roots {
            if let snap = findSelection(in: root, context: context) {
                return snap
            }
        }

        lastElement = nil
        return nil
    }

    private func resetCacheIfNeeded(for context: SelectionFetchContext) {
        guard lastProcessIdentifier != context.processIdentifier else { return }
        lastProcessIdentifier = context.processIdentifier
        lastElement = nil
        lastRectPoints = nil
    }

    private func snapshot(from element: AXUIElement, context: SelectionFetchContext) -> SelectionSnapshot? {
        let markerRange = selectedTextMarkerRange(in: element)
        let text = directSelectedText(in: element) ?? markerRange.flatMap { stringForTextMarkerRange($0, in: element) }

        guard let text, !text.isEmpty else { return nil }

        let preciseRects = selectionRects(in: element, markerRange: markerRange, context: context)
        let rect = bestRect(preciseRects, context: context) ?? elementFrame(element, context: context)

        guard let rect, isUsable(rect) else { return nil }
        lastRectPoints = rect
        lastElement = element

        return SelectionSnapshot(
            text: text,
            rect: rect,
            isTextFinal: true,
            appBundleID: context.bundleID,
            pageURL: nil
        )
    }

    private func findSelection(in root: AXUIElement, context: SelectionFetchContext) -> SelectionSnapshot? {
        var visited = Set<CFHashCode>()
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0

        while index < queue.count && visited.count < maxSearchNodes {
            let (element, depth) = queue[index]
            index += 1

            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }

            if let snap = snapshot(from: element, context: context) {
                return snap
            }

            guard depth < maxSearchDepth else { continue }

            for child in copyElementArray(element, kAXSelectedChildrenAttribute as CFString) {
                queue.append((child, depth + 1))
            }

            for child in copyElementArray(element, kAXChildrenAttribute as CFString) {
                queue.append((child, depth + 1))
            }
        }

        return nil
    }

    private func directSelectedText(in element: AXUIElement) -> String? {
        let text = (copyAttribute(element, kAXSelectedTextAttribute as CFString) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func selectedTextMarkerRange(in element: AXUIElement) -> AnyObject? {
        guard let markerRange = copyAttribute(element, axSelectedTextMarkerRangeAttribute),
              CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID() else { return nil }
        return markerRange
    }

    private func stringForTextMarkerRange(_ markerRange: AnyObject, in element: AXUIElement) -> String? {
        let text = (copyParameterizedAttribute(
            element,
            axStringForTextMarkerRangeParameterizedAttribute,
            parameter: markerRange
        ) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func selectionRects(in element: AXUIElement, markerRange: AnyObject?, context: SelectionFetchContext) -> [CGRect] {
        var rects: [CGRect] = []

        if let selectedRange = axValue(copyAttribute(element, kAXSelectedTextRangeAttribute as CFString)),
           let rect = boundsForSelectedRange(selectedRange, in: element, context: context) {
            rects.append(rect)
        }

        let rangeRects = copyAXValueArray(element, kAXSelectedTextRangesAttribute as CFString)
            .compactMap { boundsForSelectedRange($0, in: element, context: context) }

        if !rangeRects.isEmpty {
            rects.append(rangeRects.reduce(CGRect.null) { $0.union($1) })
        }

        if let markerRange,
           let rect = boundsForTextMarkerRange(markerRange, in: element, context: context) {
            rects.append(rect)
        }

        return rects
    }

    private func boundsForSelectedRange(_ range: AXValue, in element: AXUIElement, context: SelectionFetchContext) -> CGRect? {
        guard let rawRect = rectValue(copyParameterizedAttribute(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            parameter: range
        )) else { return nil }

        return convertAXScreenRect(rawRect, context: context)
    }

    private func boundsForTextMarkerRange(_ markerRange: AnyObject, in element: AXUIElement, context: SelectionFetchContext) -> CGRect? {
        guard let rawRect = rectValue(copyParameterizedAttribute(
            element,
            axBoundsForTextMarkerRangeParameterizedAttribute,
            parameter: markerRange
        )) else { return nil }

        return convertAXScreenRect(rawRect, context: context)
    }

    private func elementFrame(_ element: AXUIElement, context: SelectionFetchContext) -> CGRect? {
        guard
            let positionValue = axValue(copyAttribute(element, kAXPositionAttribute as CFString)),
            let sizeValue = axValue(copyAttribute(element, kAXSizeAttribute as CFString))
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        return convertAXTopLeftPointsRect(CGRect(origin: point, size: size), context: context)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var obj: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute, &obj)
        guard err == .success else { return nil }
        return obj
    }

    private func copyParameterizedAttribute(_ element: AXUIElement, _ attribute: CFString, parameter: AnyObject) -> AnyObject? {
        var obj: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &obj)
        guard err == .success else { return nil }
        return obj
    }

    private func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let obj = copyAttribute(element, attribute),
              CFGetTypeID(obj) == AXUIElementGetTypeID() else { return nil }
        return (obj as! AXUIElement)
    }

    private func copyElementArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
        guard let array = copyAttribute(element, attribute) as? [AnyObject] else { return [] }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement)
        }
    }

    private func copyAXValueArray(_ element: AXUIElement, _ attribute: CFString) -> [AXValue] {
        guard let array = copyAttribute(element, attribute) as? [AnyObject] else { return [] }
        return array.compactMap { axValue($0) }
    }

    private func appendUnique(_ element: AXUIElement?, to elements: inout [AXUIElement], seen: inout Set<CFHashCode>) {
        guard let element else { return }
        let hash = CFHash(element)
        guard seen.insert(hash).inserted else { return }
        elements.append(element)
    }

    private func axValue(_ obj: AnyObject?) -> AXValue? {
        guard let obj, CFGetTypeID(obj) == AXValueGetTypeID() else { return nil }
        return (obj as! AXValue)
    }

    private func rectValue(_ obj: AnyObject?) -> CGRect? {
        guard let value = axValue(obj), AXValueGetType(value) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    private func convertAXScreenRect(_ rect: CGRect, context: SelectionFetchContext) -> CGRect? {
        bestRect([
            convertAXTopLeftPointsRect(rect, context: context),
            convertAXTopLeftPixelsRect(rect, context: context)
        ], context: context)
    }

    private func convertAXTopLeftPointsRect(_ rect: CGRect, context: SelectionFetchContext) -> CGRect? {
        guard isUsable(rect) else { return nil }
        guard let referenceScreen = context.screens.first(where: { $0.frame.origin == .zero }) ?? context.mainScreen else {
            return nil
        }

        return CGRect(
            x: rect.origin.x,
            y: referenceScreen.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func convertAXTopLeftPixelsRect(_ rect: CGRect, context: SelectionFetchContext) -> CGRect? {
        guard isUsable(rect) else { return nil }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let matchedScreen = context.screens.first { screen in
            guard let bounds = screen.cgBounds else { return false }
            return bounds.contains(center)
        } ?? context.mainScreen

        guard let screen = matchedScreen, let boundsPx = screen.cgBounds else { return nil }
        guard boundsPx.width > 0, screen.frame.width > 0 else { return nil }

        let scale = boundsPx.width / screen.frame.width
        return CGRect(
            x: screen.frame.minX + (rect.origin.x - boundsPx.origin.x) / scale,
            y: screen.frame.maxY - ((rect.origin.y - boundsPx.origin.y) + rect.height) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    private func bestRect(_ rects: [CGRect?], context: SelectionFetchContext) -> CGRect? {
        rects
            .compactMap { $0 }
            .filter(isUsable)
            .max { score($0, context: context) < score($1, context: context) }
    }

    private func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= 1
        && rect.height >= 1
        && rect.origin.x.isFinite
        && rect.origin.y.isFinite
        && rect.width.isFinite
        && rect.height.isFinite
        && !rect.isNull
    }

    private func score(_ rect: CGRect, context: SelectionFetchContext) -> CGFloat {
        var score: CGFloat = 0

        for screen in context.screens {
            let frame = screen.visibleFrame.insetBy(dx: -80, dy: -80)
            if frame.intersects(rect) {
                score += 1_000
                score += min(frame.intersection(rect).area / max(frame.area, 1), 1) * 100
            }
            if frame.contains(rect.center) {
                score += 200
            }
            if rect.width > screen.frame.width * 0.95 {
                score -= 150
            }
            if rect.height > screen.frame.height * 0.6 {
                score -= 150
            }
        }

        if let lastRectPoints {
            score -= min(distance(from: rect.center, to: lastRectPoints), 240)
        }

        score -= min(distance(from: context.mouseLocation, to: rect) / 4, 120)
        return score
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
