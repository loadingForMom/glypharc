//
//  PanelPlacement.swift
//  GlyphArc
//

import AppKit

enum PanelPlacement {
    static func controlOrigin(near rect: CGRect, size: CGSize) -> CGPoint {
        let screenFrame = visibleFrame(for: rect).insetBy(dx: 8, dy: 8)
        let x = clamp(rect.midX - size.width / 2, min: screenFrame.minX, max: screenFrame.maxX - size.width)
        let y = adjacentY(near: rect, height: size.height, in: screenFrame)
        return CGPoint(x: x, y: y)
    }

    static func clampedOrigin(_ origin: CGPoint, size: CGSize, near rect: CGRect) -> CGPoint {
        let screenFrame = visibleFrame(for: rect).insetBy(dx: 8, dy: 8)
        return CGPoint(
            x: clamp(origin.x, min: screenFrame.minX, max: screenFrame.maxX - size.width),
            y: clamp(origin.y, min: screenFrame.minY, max: screenFrame.maxY - size.height)
        )
    }

    static func resultOrigin(near rect: CGRect, size: CGSize) -> CGPoint {
        let screenFrame = visibleFrame(for: rect).insetBy(dx: 10, dy: 10)
        let margin: CGFloat = 12

        let rightX = rect.maxX + margin
        let leftX = rect.minX - margin - size.width

        let x: CGFloat
        if rightX + size.width <= screenFrame.maxX {
            x = rightX
        } else if leftX >= screenFrame.minX {
            x = leftX
        } else {
            x = clamp(rect.midX - size.width / 2, min: screenFrame.minX, max: screenFrame.maxX - size.width)
        }

        let y = adjacentY(near: rect, height: size.height, in: screenFrame)
        return CGPoint(x: x, y: y)
    }

    private static func adjacentY(near rect: CGRect, height: CGFloat, in frame: CGRect) -> CGFloat {
        let margin: CGFloat = 12
        let above = rect.maxY + margin
        let below = rect.minY - margin - height

        if above + height <= frame.maxY {
            return above
        }
        if below >= frame.minY {
            return below
        }
        return clamp(rect.midY - height / 2, min: frame.minY, max: frame.maxY - height)
    }

    private static func visibleFrame(for rect: CGRect) -> CGRect {
        if let containing = NSScreen.screens.first(where: { $0.visibleFrame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            return containing.visibleFrame
        }

        if let intersecting = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(rect).area < $1.visibleFrame.intersection(rect).area
        }), intersecting.visibleFrame.intersects(rect) {
            return intersecting.visibleFrame
        }

        if let nearest = NSScreen.screens.min(by: {
            distance(from: rect.center, to: $0.visibleFrame) < distance(from: rect.center, to: $1.visibleFrame)
        }) {
            return nearest.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? rect
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else { return minValue }
        return Swift.min(Swift.max(value, minValue), maxValue)
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
