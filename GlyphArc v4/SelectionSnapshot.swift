//
//  SelectionSnapshot.swift
//  GlyphArc v4
//
//  Created by Sasha on 12/19/25.
//


import Foundation
import CoreGraphics

struct SelectionSnapshot: Equatable, Sendable {
    let text: String
    let rect: CGRect                 // AppKit points (origin bottom-left)
    let isTextFinal: Bool
    let appBundleID: String?
    let pageURL: String?

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUsableText: Bool {
        isTextFinal && !trimmedText.isEmpty
    }

    static func == (lhs: SelectionSnapshot, rhs: SelectionSnapshot) -> Bool {
        lhs.text == rhs.text &&
        lhs.rect == rhs.rect &&
        lhs.isTextFinal == rhs.isTextFinal &&
        lhs.appBundleID == rhs.appBundleID &&
        lhs.pageURL == rhs.pageURL
    }
}
