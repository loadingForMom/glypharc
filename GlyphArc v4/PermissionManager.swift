//
//  PermissionManager.swift
//  GlyphArc v4
//
//  Created by Sasha on 12/19/25.
//


import Foundation
@preconcurrency import ApplicationServices

@MainActor
final class PermissionManager {

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        requestAccessibilityIfNeeded()
    }

    func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
