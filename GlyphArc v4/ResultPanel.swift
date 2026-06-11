//
//  ResultPanel.swift
//  GlyphArc v4
//
//  Created by Sasha on 12/19/25.
//

import AppKit
import Observation
import SwiftUI

@MainActor
final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ResultPanelController {

    private let appState: AppState
    private var panel: ResultPanel?
    private var isObserving = false

    private let panelSize = CGSize(width: 420, height: 280)

    init(appState: AppState) {
        self.appState = appState
        bind()
    }

    private func bind() {
        guard !isObserving else { return }
        isObserving = true
        observeResultState()
        syncPanel()
    }

    private func observeResultState() {
        withObservationTracking {
            _ = appState.isLoading
            _ = appState.resultText
            _ = appState.lastError
            _ = appState.selection?.rect
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeResultState()
                self.syncPanel()
            }
        }
    }

    private func syncPanel() {
        let hasResult = !appState.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasError = (appState.lastError?.isEmpty == false)

        guard let rect = appState.selection?.rect else {
            hide()
            return
        }

        if appState.isLoading || hasResult || hasError {
            show(near: rect)
        } else {
            hide()
        }
    }

    func show(near rect: CGRect) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        panel.orderFrontRegardless()
        panel.setFrameOrigin(PanelPlacement.resultOrigin(near: rect, size: panel.frame.size))
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let p = ResultPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true

        let root = ResultPanelContent(
            close: { [weak self] in self?.hide() }
        )
        .environment(appState)
        .frame(width: panelSize.width, height: panelSize.height)

        p.contentView = NSHostingView(rootView: root)
        panel = p
    }
}

@MainActor
private struct ResultPanelContent: View {
    @Environment(AppState.self) private var appState
    let close: () -> Void

    private var displayText: String {
        if !appState.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appState.resultText
        }
        return appState.lastError ?? "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appState.isLoading ? "Thinking..." : "Result")
                    .font(.headline)
                Spacer()
                Button("Close", action: close)
            }

            ScrollView {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .overlay {
                if appState.isLoading && appState.resultText.isEmpty {
                    ProgressView()
                }
            }
        }
        .padding(12)
    }
}
