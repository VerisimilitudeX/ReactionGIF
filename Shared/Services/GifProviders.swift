import Foundation

/// Searches Tenor and Giphy (or the backend proxy) and merges the results so we
/// get variety across both libraries.
struct GifProviders {
    func search(_ query: String, safeMode: Bool) async -> [GifCandidate] {
        if !AppConfig.backendBaseURL.isEmpty {
            return await searchBackend(query, safeMode: safeMode)
        }
        async let tenor = searchTenor(query, safeMode: safeMode)
        async let giphy = searchGiphy(query, safeMode: safeMode)
        let (tenorResults, giphyResults) = await (tenor, giphy)

        // Interleave so the top picks alternate between providers.
        var merged: [GifCandidate] = []
        let maxCount = max(tenorResults.count, giphyResults.count)
        for index in 0..<maxCount {
            if index < tenorResults.count { merged.append(tenorResults[index]) }
            if index < giphyResults.count { merged.append(giphyResults[index]) }
        }
        return merged
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

    private func searchTenor(_ query: String, safeMode: Bool) async -> [GifCandidate] {
        guard !Secrets.tenorAPIKey.isEmpty,
              var components = URLComponents(string: "https://tenor.googleapis.com/v2/search") else {
            return []
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
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
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
    }

    // MARK: Giphy

    private func searchGiphy(_ query: String, safeMode: Bool) async -> [GifCandidate] {
        guard !Secrets.giphyAPIKey.isEmpty,
              var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Secrets.giphyAPIKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(AppConfig.resultLimit)"),
            URLQueryItem(name: "rating", value: safeMode ? "g" : AppConfig.giphyRating),
            URLQueryItem(name: "bundle", value: "messaging_non_clips")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
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
    }
}
