//
//  GlyphArcApp.swift
//  GlyphArc
//

import SwiftUI

@main
struct GlyphArcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("GlyphArc", systemImage: "text.cursor") {
            MenuBarContent()
                .environment(appDelegate.container.appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appDelegate.container.appState)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Toggle("Включено", isOn: $appState.enabled)

        Divider()

        Button("Очистить результат") {
            appState.clearResult()
        }
        .disabled(appState.resultText.isEmpty && appState.lastError == nil)

        Button("Panic wipe") {
            appState.panicWipe()
        }

        SettingsLink {
            Text("Настройки")
        }

        Divider()

        Button("Quit GlyphArc") {
            NSApplication.shared.terminate(nil)
        }
    }
}
