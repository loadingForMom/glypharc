//
//  HoverMorphMenuView.swift
//  GlyphArc
//

import AppKit
import Observation
import SwiftUI

@MainActor
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class OverlayMotionState {
    var blurRadius: CGFloat = 0
}

@MainActor
final class HoverMorphMenuView: NSHostingView<HoverMorphMenuRoot> {
    required init(rootView: HoverMorphMenuRoot) {
        super.init(rootView: rootView)
    }

    init(
        appState: AppState,
        motionState: OverlayMotionState,
        requestResize: @escaping @MainActor (CGSize, TimeInterval) -> Void,
        setFreezePosition: @escaping @MainActor (Bool) -> Void
    ) {
        super.init(rootView: HoverMorphMenuRoot(
            appState: appState,
            motionState: motionState,
            requestResize: requestResize,
            setFreezePosition: setFreezePosition
        ))
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
struct HoverMorphMenuRoot: View {
    var appState: AppState
    var motionState: OverlayMotionState

    let requestResize: @MainActor (CGSize, TimeInterval) -> Void
    let setFreezePosition: @MainActor (Bool) -> Void

    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?

    private let collapsedSize = CGSize(width: 56, height: 56)
    private let expandedSize = CGSize(width: 196, height: 56)

    private var hasText: Bool {
        appState.selection?.hasUsableText == true
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("GlyphArc actions")

                if isExpanded {
                    actionButton(title: "Перевести", systemImage: "character.book.closed", action: .translate)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    actionButton(title: "Объяснить", systemImage: "lightbulb", action: .explain)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 8)
            .frame(width: isExpanded ? expandedSize.width : collapsedSize.width, height: collapsedSize.height)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 7)
        }
        .frame(width: isExpanded ? expandedSize.width : collapsedSize.width, height: collapsedSize.height)
        .blur(radius: motionState.blurRadius)
        .onHover { hovering in
            handleHover(hovering)
        }
        .onAppear {
            requestResize(collapsedSize, 0)
        }
        .onChange(of: isExpanded) { _, expanded in
            requestResize(expanded ? expandedSize : collapsedSize, 0.18)
        }
        .onDisappear {
            collapseTask?.cancel()
        }
    }

    private func handleHover(_ hovering: Bool) {
        collapseTask?.cancel()

        if hovering {
            setFreezePosition(true)
            withAnimation(.smooth(duration: 0.2)) {
                isExpanded = true
            }
            return
        }

        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.smooth(duration: 0.22)) {
                isExpanded = false
            }

            try? await Task.sleep(nanoseconds: 230_000_000)
            guard !Task.isCancelled else { return }
            setFreezePosition(false)
        }
    }

    private func actionButton(title: String, systemImage: String, action: AppState.GlyphArcActionKind) -> some View {
        Button {
            collapseTask?.cancel()
            appState.runAI(action)
            withAnimation(.snappy(duration: 0.18)) {
                isExpanded = false
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 62, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasText ? .primary : .secondary)
        .disabled(!hasText || appState.isLoading)
        .accessibilityLabel(title)
    }
}
