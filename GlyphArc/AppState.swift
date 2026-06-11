//
//  AppState.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//

import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
final class AppState {

    enum GlyphArcActionKind: String, CaseIterable, Identifiable {
        case translate = "Перевести"
        case explain = "Объяснить"
        var id: String { rawValue }
    }

    // MARK: Settings (RAM-only)
    var enabled: Bool = true
    var model: String = "gpt-4o-mini"

    /// Не сохраняем на диск. Просто настройка на время запуска.
    var apiBaseURL: String = "http://localhost:1234/v1"
    private var apiKey: String = ""

    // MARK: Runtime
    private(set) var selection: SelectionSnapshot? = nil

    var resultText: String = ""
    var isLoading: Bool = false

    /// Ошибки AI/сети (показываем в ResultPanel/Settings).
    var lastError: String? = nil

    /// Ошибки pipeline выделения. Не должны открывать ResultPanel.
    var selectionError: String? = nil

    @ObservationIgnored private let client = OpenAIClient()
    @ObservationIgnored private var aiTask: Task<Void, Never>?

    // MARK: Key helpers for UI
    var apiKeyTail: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "none" }
        return String(trimmed.suffix(4))
    }

    func saveAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearAPIKey() {
        apiKey = ""
    }

    // MARK: Selection
    func setSelection(_ snap: SelectionSnapshot?) {
        selection = snap
    }

    // MARK: Panic wipe (RAM-only)
    func panicWipe() {
        aiTask?.cancel()
        aiTask = nil
        selection = nil
        resultText = ""
        isLoading = false
        lastError = nil
        selectionError = nil
    }

    // MARK: AI
    func runAI(_ action: GlyphArcActionKind, inputText: String? = nil) {
        guard enabled else { return }
        guard !isLoading else { return }

        let baseText = inputText
        ?? (selection?.hasUsableText == true ? selection?.trimmedText : nil)
        ?? ""

        let text = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        aiTask?.cancel()
        lastError = nil
        isLoading = true

        let prompt = buildPrompt(action: action, text: text)
        let model = self.model
        let baseURLString = self.apiBaseURL
        let apiKey = self.apiKey
        let client = self.client

        aiTask = Task(priority: .userInitiated) { [client, model, baseURLString, apiKey, prompt] in
            do {
                let out = try await client.runText(
                    model: model,
                    instructions: "Ты помощник. Отвечай кратко и по делу.",
                    input: prompt,
                    baseURLString: baseURLString,
                    apiKey: apiKey
                )

                guard !Task.isCancelled else { return }
                self.resultText = out
                self.isLoading = false
                self.aiTask = nil
            } catch is CancellationError {
                self.isLoading = false
                self.aiTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.isLoading = false
                self.aiTask = nil
            }
        }
    }

    func clearResult() {
        resultText = ""
        lastError = nil
    }

    private func buildPrompt(action: GlyphArcActionKind, text: String) -> String {
        switch action {
        case .translate:
            return """
            Переведи на русский. Сохраняй смысл, стиль и термины.

            Текст:
            \(text)
            """
        case .explain:
            return """
            Объясни простыми словами, что это значит. Если есть термины — расшифруй.

            Текст:
            \(text)
            """
        }
    }
}
