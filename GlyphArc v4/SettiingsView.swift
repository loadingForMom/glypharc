//
//  SettiingsView.swift
//  GlyphArc v4
//
//  Created by Sasha on 12/19/25.
//

import SwiftUI
@preconcurrency import ApplicationServices

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyDraft: String = ""
    @State private var permissionRefresh = UUID()

    var body: some View {
        @Bindable var appState = appState

        Form {
            Toggle("Включено", isOn: $appState.enabled)

            TextField("Модель", text: $appState.model)
                .autocorrectionDisabled(true)

            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    isGranted: AXIsProcessTrusted(),
                    request: requestAccessibility
                )
            }
            .id(permissionRefresh)

            Divider()

            TextField("API Base URL", text: $appState.apiBaseURL)
                .autocorrectionDisabled(true)

            Text("OpenAI: https://api.openai.com/v1   •   Local (LM Studio): http://localhost:1234/v1")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("OpenAI API Key", text: $apiKeyDraft)

            HStack {
                Button("Use Key") {
                    appState.saveAPIKey(apiKeyDraft)
                    apiKeyDraft = ""
                }
                Button("Clear Key") {
                    appState.clearAPIKey()
                    apiKeyDraft = ""
                }
                Spacer()
                Text("In use: ••••\(appState.apiKeyTail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Panic wipe (clear RAM)") {
                appState.panicWipe()
            }

            if let err = appState.lastError, !err.isEmpty {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let err = appState.selectionError, !err.isEmpty {
                Text(err)
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func permissionRow(title: String, isGranted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isGranted ? "Granted" : "Missing")
                .font(.caption)
                .foregroundStyle(isGranted ? .green : .orange)
            Button("Request") {
                request()
                permissionRefresh = UUID()
            }
            .disabled(isGranted)
        }
    }

    private func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
