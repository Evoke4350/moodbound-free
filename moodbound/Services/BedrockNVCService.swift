import Foundation

enum BedrockNVCError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Bedrock."
        case .serverError(let message):
            return message
        case .emptyOutput:
            return "Model returned no text."
        }
    }
}

struct BedrockNVCService {
    struct Config {
        var region: String = "us-east-1"
        var modelID: String = "us.amazon.nova-2-lite-v1:0"
        var token: String

        static func live() -> Config {
            let env = ProcessInfo.processInfo.environment["AWS_BEARER_TOKEN_BEDROCK"] ?? ""
            guard !env.isEmpty else {
                fatalError("AWS_BEARER_TOKEN_BEDROCK environment variable is required")
            }
            return Config(token: env)
        }
    }

    private struct ConverseRequest: Encodable {
        struct Message: Encodable {
            struct Content: Encodable {
                let text: String
            }
            let role: String
            let content: [Content]
        }

        struct InferenceConfig: Encodable {
            let maxTokens: Int
            let temperature: Double
            let topP: Double
        }

        let messages: [Message]
        let system: [Message.Content]
        let inferenceConfig: InferenceConfig
    }

    private struct ConverseResponse: Decodable {
        struct Output: Decodable {
            struct Message: Decodable {
                struct Content: Decodable {
                    let text: String?
                }
                let content: [Content]
            }
            let message: Message?
        }
        let output: Output?
    }

    private let session: URLSession
    private let config: Config

    init(config: Config = .live(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func rephrase(input: String) async throws -> String {
        let escapedModelID = config.modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.modelID
        guard let url = URL(string: "https://bedrock-runtime.\(config.region).amazonaws.com/model/\(escapedModelID)/converse") else {
            throw BedrockNVCError.invalidResponse
        }

        let payload = ConverseRequest(
            messages: [
                .init(
                    role: "user",
                    content: [.init(text: input)]
                )
            ],
            system: [
                .init(text: "You are an NVC rephraser."),
                .init(text: "Rewrite user text using this exact structure: Observation, Feeling, Need, Request."),
                .init(text: "Keep intent, reduce blame, and keep it concise.")
            ],
            inferenceConfig: .init(maxTokens: 320, temperature: 0.2, topP: 0.9)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BedrockNVCError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw BedrockNVCError.serverError(text)
        }

        let decoded = try JSONDecoder().decode(ConverseResponse.self, from: data)
        let output = decoded.output?.message?.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw BedrockNVCError.emptyOutput }
        return output
    }
}
