//
//  SelectionMonitor.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//

import Foundation
import AppKit
import CoreGraphics

actor SelectionFetchWorker {
    private let fetcher = SelectionFetcher()

    func fetch(context: SelectionFetchContext) -> SelectionSnapshot? {
        fetcher.fetch(context: context)
    }
}

@MainActor
final class SelectionMonitor {
    private let appState: AppState
    private let overlay: OverlayPanelController
    private let fetchWorker: SelectionFetchWorker

    private var monitorTask: Task<Void, Never>?
    private let intervalNanoseconds: UInt64

    init(
        appState: AppState,
        overlay: OverlayPanelController,
        fetchWorker: SelectionFetchWorker = SelectionFetchWorker(),
        interval: TimeInterval = 1.0 / 60.0
    ) {
        self.appState = appState
        self.overlay = overlay
        self.fetchWorker = fetchWorker
        self.intervalNanoseconds = UInt64(max(interval, 1.0 / 240.0) * 1_000_000_000)
    }

    func start() {
        stop()

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func tick() async {
        guard appState.enabled else {
            clearSelectionAndHide()
            return
        }

        guard let context = SelectionFetchContext.current() else {
            clearSelectionAndHide()
            return
        }

        let incoming = await fetchWorker.fetch(context: context)

        guard appState.enabled else {
            clearSelectionAndHide()
            return
        }

        guard let incoming else {
            clearSelectionAndHide()
            return
        }

        let current = appState.selection
        let shouldReplace: Bool = {
            guard let current else { return true }

            // Если rect реально уехал — обновляем модель, но не переоткрываем panel.
            if !rectAlmostEqual(current.rect, incoming.rect, eps: 1.0) { return true }

            // Если изменилось наличие usable текста — тоже обновляем.
            if current.hasUsableText != incoming.hasUsableText { return true }

            if current.text != incoming.text { return true }
            if current.appBundleID != incoming.appBundleID { return true }
            if current.pageURL != incoming.pageURL { return true }

            return false
        }()

        if shouldReplace {
            appState.setSelection(incoming)
        }

        if current == nil || !overlay.isVisible {
            overlay.show(near: incoming.rect)
        } else {
            overlay.updatePositionIfNeeded(near: incoming.rect)
        }
    }

    private func clearSelectionAndHide() {
        if appState.selection != nil {
            appState.setSelection(nil)
        }
        overlay.hide()
    }

    private func rectAlmostEqual(_ a: CGRect, _ b: CGRect, eps: CGFloat) -> Bool {
        abs(a.midX - b.midX) < eps
        && abs(a.midY - b.midY) < eps
        && abs(a.width - b.width) < eps
        && abs(a.height - b.height) < eps
    }
}
