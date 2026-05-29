import Foundation
import UIKit

/// Turns a conversation screenshot into two well-timed reaction ideas.
///
/// If `AppConfig.backendBaseURL` is set, the work happens server-side (no keys on
/// device — the recommended setup for the App Store). Otherwise it calls OpenAI
/// directly using the key in `Secrets.swift` (fine for development).
struct OpenAIService {
    enum ServiceError: LocalizedError {
        case missingKey
        case badResponse(String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your OpenAI API key in Secrets.swift (or set a backend URL)."
            case .badResponse(let message):
                return "Reaction service error: \(message)"
            case .decoding(let message):
                return "Couldn't understand the AI response: \(message)"
            }
        }
    }

    func suggestReactions(
        for image: UIImage,
        vibe: Vibe,
        safeMode: Bool,
        count: Int = 6,
        excludeLabels: [String] = []
    ) async throws -> ReactionSuggestion {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw ServiceError.badResponse("Could not encode the image.")
        }
        let base64 = jpeg.base64EncodedString()

        if !AppConfig.backendBaseURL.isEmpty {
            return try await suggestViaBackend(
                base64: base64, vibe: vibe, safeMode: safeMode,
                count: count, excludeLabels: excludeLabels
            )
        }
        guard !Secrets.openAIAPIKey.isEmpty else { throw ServiceError.missingKey }
        return try await suggestViaOpenAI(
            base64: base64, vibe: vibe, safeMode: safeMode,
            count: count, excludeLabels: excludeLabels
        )
    }

    // MARK: Backend proxy

    private func suggestViaBackend(
        base64: String, vibe: Vibe, safeMode: Bool,
        count: Int, excludeLabels: [String]
    ) async throws -> ReactionSuggestion {
        guard let base = URL(string: AppConfig.backendBaseURL) else {
            throw ServiceError.badResponse("Invalid backend URL.")
        }
        var request = URLRequest(url: base.appendingPathComponent("suggest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "imageBase64": base64,
            "vibe": vibe.rawValue,
            "safeMode": safeMode,
            "count": count,
            "excludeLabels": excludeLabels
        ])
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        do {
            return try JSONDecoder().decode(ReactionSuggestion.self, from: data)
        } catch {
            throw ServiceError.decoding(error.localizedDescription)
        }
    }

    // MARK: Direct OpenAI

    private func suggestViaOpenAI(
        base64: String, vibe: Vibe, safeMode: Bool,
        count: Int, excludeLabels: [String]
    ) async throws -> ReactionSuggestion {
        let dataURL = "data:image/jpeg;base64,\(base64)"
        let safetyLine = safeMode
            ? "Keep everything strictly clean and family-friendly (G-rated)."
            : "Keep it PG-13: edgy is fine, nothing hateful, explicit, or cruel."

        let excludeBlock: String
        if excludeLabels.isEmpty {
            excludeBlock = ""
        } else {
            let list = excludeLabels.map { "\"\($0)\"" }.joined(separator: ", ")
            excludeBlock = """

            Already suggested in this session — do NOT repeat these bits or \
            anything substantially similar: \(list).
            """
        }

        let systemPrompt = """
        You pick reaction memes for Gen-Z group chats. The chat is a tight \
        friend group where people clown each other constantly. Your job: \
        look at a screenshot of the convo and pick the funniest reactions \
        to drop next.

        STEP 1 — read the whole visible chat carefully and find the \
        FUNNIEST BEAT in it. That's usually (not always) the most recent \
        message — but if the last message is short/dry/passive ("ok", \
        "lol", "yeah"), look back one or two messages for the real bit: \
        the flex, the overshare, the dumb take, the savage cut, the cope.

        STEP 2 — identify the person doing that bit (name if visible) and \
        what they literally said.

        STEP 3 — pick reactions that CLOWN that bit. Not reactions that \
        describe it. Not soft "lol that was funny" reactions. Sharp, \
        specific, friend-group clowns.

        What lands here (9/10):
          • Roasts of whoever is doing the bit. Default to clowning.
          • Meme IMAGE MACROS with bold caption text. Not loopy emotion GIFs.
          • Named templates the audience already recognizes.

        Template vocabulary — copy the search_query VERBATIM (or a very \
        close variant) so Tenor/Giphy actually return the right image:

          • "does he know meme" — they missed something obvious / out of loop
          • "he doesn't know meme" — same family
          • "how did he know" — they said something painfully obvious as if profound
          • "bro thinks he's him" — they flexed and the flex didn't land
          • "who invited my man blud" — NBA bench-warmer roast of fake confidence
          • "this man yapping" — they rambled / overshared
          • "say less gif" — shut them up sarcastically
          • "bro got cooked" / "ratio'd gif" — they took an L
          • "ice cold" / "savage gif" — honoring a clean cut someone else made
          • "crashout meme" / "mental breakdown gif" — chaos / meltdown
          • "polygraph meme" / "lie detector meme" — sarcastic vibe check
          • "penguin walking away meme" — bit/exit after a dumb take
          • "side eye monkey" — judgmental glance
          • "mocking spongebob" — mocking imitation (chicken pose, NOT "this is Patrick")
          • "stop the cap" / "yeah right gif" — calling out a stretch
          • "joaquin phoenix laughing" / "deceased emoji" — they said something fire
          • "real gif" / "no fr fr" / "facts gif" — genuine agreement (rare)

        DO NOT use vague queries like "happy", "sad", "shocked", "funny", \
        "annoyed", "thinking", "confused" — these return generic stock GIFs \
        that nobody sends. ALWAYS use a named template above.
        \(excludeBlock)

        Energy this round: \(vibe.promptHint)
        \(safetyLine)
        Tease the bit/message, never the person — no jokes at protected \
        traits or things someone can't change.

        Respond ONLY with strict JSON:
        {
          "read_back": "<one short sentence naming who did what — e.g. 'Saahil overshared, Aden cold-cut him, Saahil took it'>",
          "options": [
            {"label": "<2-4 word name for the bit>", "search_query": "<NAMED template from the vocab above>", "why": "<one short sentence on why this clowns the specific moment>"}
            // exactly \(count) entries, all meaningfully different from each other
          ]
        }

        Return EXACTLY \(count) options. Each option must clown a different \
        angle of the same moment (the flex, the cope, the dunk, the cringe) \
        OR clown a different person in the same convo. No two options \
        should use the same template.
        """

        let userContent: [[String: Any]] = [
            ["type": "text", "text": "Here is the conversation. Pick the 2 best reactions to send next."],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]
        let body: [String: Any] = [
            "model": AppConfig.openAIModel,
            "response_format": ["type": "json_object"],
            "messages": messages
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8)
        else {
            throw ServiceError.decoding("Unexpected response envelope.")
        }

        do {
            return try JSONDecoder().decode(ReactionSuggestion.self, from: contentData)
        } catch {
            throw ServiceError.decoding(error.localizedDescription)
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.badResponse(message)
        }
    }
}
