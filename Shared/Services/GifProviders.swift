import Foundation

/// Result of a GIF search: the candidates plus whether a provider told us we're
/// rate-limited, so the UI can show an accurate message instead of "no GIFs".
struct GifSearchResult {
    var candidates: [GifCandidate]
    var rateLimited: Bool
}

/// Searches Tenor and Giphy (or the backend proxy) and merges the results so we
/// get variety across both libraries.
struct GifProviders {
    func search(_ query: String, safeMode: Bool) async -> GifSearchResult {
        if !AppConfig.backendBaseURL.isEmpty {
            return GifSearchResult(candidates: await searchBackend(query, safeMode: safeMode),
                                   rateLimited: false)
        }
        async let tenor = searchTenor(query, safeMode: safeMode)
        async let giphy = searchGiphy(query, safeMode: safeMode)
        let (tenorResult, giphyResult) = await (tenor, giphy)

        // Interleave so the top picks alternate between providers.
        var merged: [GifCandidate] = []
        let maxCount = max(tenorResult.candidates.count, giphyResult.candidates.count)
        for index in 0..<maxCount {
            if index < tenorResult.candidates.count { merged.append(tenorResult.candidates[index]) }
            if index < giphyResult.candidates.count { merged.append(giphyResult.candidates[index]) }
        }
        return GifSearchResult(candidates: merged,
                               rateLimited: tenorResult.rateLimited || giphyResult.rateLimited)
    }

    // MARK: Backend proxy

    private func searchBackend(_ query: String, safeMode: Bool) async -> [GifCandidate] {
        guard let base = URL(string: AppConfig.backendBaseURL),
              var components = URLComponents(url: base.appendingPathComponent("search"),
                                             resolvingAgainstBaseURL: false) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "safe", value: safeMode ? "true" : "false")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let candidates = try? JSONDecoder().decode([GifCandidate].self, from: data) else {
            return []
        }
        return candidates
    }

    // MARK: Tenor

    private func searchTenor(_ query: String, safeMode: Bool) async -> GifSearchResult {
        guard !Secrets.tenorAPIKey.isEmpty,
              var components = URLComponents(string: "https://tenor.googleapis.com/v2/search") else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: Secrets.tenorAPIKey),
            URLQueryItem(name: "client_key", value: AppConfig.tenorClientKey),
            URLQueryItem(name: "limit", value: "\(AppConfig.resultLimit)"),
            URLQueryItem(name: "media_filter", value: "gif,tinygif"),
            URLQueryItem(name: "contentfilter", value: safeMode ? "high" : AppConfig.tenorContentFilter)
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url) else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }
        if Self.isRateLimited(response) {
            return GifSearchResult(candidates: [], rateLimited: true)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }

        let candidates: [GifCandidate] = results.compactMap { item in
            guard let media = item["media_formats"] as? [String: Any],
                  let gif = media["gif"] as? [String: Any],
                  let urlString = gif["url"] as? String,
                  let gifURL = URL(string: urlString) else { return nil }
            let previewString = (media["tinygif"] as? [String: Any])?["url"] as? String
            let title = (item["content_description"] as? String) ?? query
            return GifCandidate(provider: "Tenor",
                                gifURL: gifURL,
                                previewURL: previewString.flatMap { URL(string: $0) },
                                title: title)
        }
        return GifSearchResult(candidates: candidates, rateLimited: false)
    }

    // MARK: Giphy

    private func searchGiphy(_ query: String, safeMode: Bool) async -> GifSearchResult {
        guard !Secrets.giphyAPIKey.isEmpty,
              var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search") else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Secrets.giphyAPIKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(AppConfig.resultLimit)"),
            URLQueryItem(name: "rating", value: safeMode ? "g" : AppConfig.giphyRating),
            URLQueryItem(name: "bundle", value: "messaging_non_clips")
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url) else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }
        if Self.isRateLimited(response) {
            return GifSearchResult(candidates: [], rateLimited: true)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }
        // Giphy returns 200 with meta.status 429 in some throttle cases.
        if let meta = json["meta"] as? [String: Any], (meta["status"] as? Int) == 429 {
            return GifSearchResult(candidates: [], rateLimited: true)
        }
        guard let results = json["data"] as? [[String: Any]] else {
            return GifSearchResult(candidates: [], rateLimited: false)
        }

        let candidates: [GifCandidate] = results.compactMap { item in
            guard let images = item["images"] as? [String: Any],
                  let original = images["original"] as? [String: Any],
                  let urlString = original["url"] as? String,
                  let gifURL = URL(string: urlString) else { return nil }
            let previewString = (images["fixed_width_small"] as? [String: Any])?["url"] as? String
            let title = (item["title"] as? String) ?? query
            return GifCandidate(provider: "Giphy",
                                gifURL: gifURL,
                                previewURL: previewString.flatMap { URL(string: $0) },
                                title: title)
        }
        return GifSearchResult(candidates: candidates, rateLimited: false)
    }

    private static func isRateLimited(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse)?.statusCode == 429
    }
}
