//
//  OpenAIClient.swift
//  GlyphArc
//
//  Created by Sasha on 12/19/25.
//


import Foundation

struct OpenAIClient: Sendable {

    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidBaseURL(String)
        case badStatus(Int, String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key не задан"
            case .invalidBaseURL(let s):
                return "Неверный API Base URL: \(s)"
            case .badStatus(let code, let body):
                return "HTTP \(code): \(body)"
            case .emptyOutput:
                return "Пустой ответ модели"
            }
        }
    }

    private let session: URLSession

    init() {
        self.session = Self.makeEphemeralSession()
    }

    private static func makeEphemeralSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCredentialStorage = nil
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }

    func runText(
        model: String,
        instructions: String?,
        input: String,
        baseURLString: String,
        apiKey: String?
    ) async throws -> String {

        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedBase) else {
            throw ClientError.invalidBaseURL(baseURLString)
        }

        let endpoint = baseURL.appendingPathComponent("responses")

        let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isOpenAIHost = (baseURL.host == "api.openai.com" || baseURL.host?.hasSuffix("openai.com") == true)

        if isOpenAIHost {
            guard let apiKey, !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        }

        var payload: [String: Any] = [
            "model": model,
            "input": input,
            // Чтобы локальные сервера (LM Studio и т.п.) не держали соединение как SSE
            "stream": false
        ]
        if let instructions, !instructions.isEmpty {
            payload["instructions"] = instructions
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        req.httpBody = data

        let (respData, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClientError.badStatus(-1, "No HTTPURLResponse")
        }

        if !(200...299).contains(http.statusCode) {
            let body = String(data: respData, encoding: .utf8) ?? "<no body>"
            throw ClientError.badStatus(http.statusCode, body)
        }

        // 1) OpenAI Responses API style
        if let text = parseResponsesAPI(respData) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 2) Chat Completions style fallback
        if let text = parseChatCompletions(respData) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        throw ClientError.emptyOutput
    }

    private func parseResponsesAPI(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = json as? [String: Any],
            let output = dict["output"] as? [[String: Any]]
        else { return nil }

        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for c in content {
                if (c["type"] as? String) == "output_text",
                   let t = c["text"] as? String {
                    parts.append(t)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func parseChatCompletions(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = json as? [String: Any],
            let choices = dict["choices"] as? [[String: Any]]
        else { return nil }

        // most common: choices[0].message.content
        for ch in choices {
            if let msg = ch["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.isEmpty {
                return content
            }
            // alt: choices[0].text
            if let t = ch["text"] as? String, !t.isEmpty {
                return t
            }
        }
        return nil
    }
}
