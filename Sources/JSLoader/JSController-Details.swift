//
//  JSController-Details.swift
//  Sulfur
//
//  Created by Francesco on 30/03/25.
//

import Sybau
import JavaScriptCore

extension JSController {
    
    // MARK: - HTML-based details (synchronous JS)
    
    /// Fetches the page at `url`, then passes the HTML to the synchronous JS functions
    /// `extractDetails` and `extractEpisodes`.
    func fetchDetails(
        url: String,
        completion: @escaping @Sendable ([MediaItem], [EpisodeLink]) -> Void
    ) {
        guard let url = URL(string: url) else {
            Logger.shared.log("Invalid details URL: \(url)", type: "Error")
            completion([], [])
            return
        }
        
        URLSession.custom.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            
            if let error {
                Logger.shared.log("Network error in fetchDetails: \(error)", type: "Error")
                DispatchQueue.main.async { completion([], []) }
                return
            }
            
            guard let data, let html = String(data: data, encoding: .utf8) else {
                Logger.shared.log("Failed to decode HTML in fetchDetails", type: "Error")
                DispatchQueue.main.async { completion([], []) }
                return
            }
            
            Logger.shared.log(html, type: "HTMLStrings")
            
            var resultItems: [MediaItem] = []
            if
                let parseFunction = self.context.objectForKeyedSubscript("extractDetails"),
                let results = parseFunction.call(withArguments: [html]).toArray() as? [[String: String]]
            {
                resultItems = results.map {
                    MediaItem(
                        description: $0["description"] ?? "",
                        aliases: $0["aliases"] ?? "",
                        airdate: $0["airdate"] ?? ""
                    )
                }
            } else {
                Logger.shared.log("Failed to parse extractDetails results", type: "Error")
            }
            
            var episodeLinks: [EpisodeLink] = []
            if
                let episodesFunction = self.context.objectForKeyedSubscript("extractEpisodes"),
                let episodes = episodesFunction.call(withArguments: [html]).toArray() as? [[String: String]]
            {
                episodeLinks = episodes.compactMap { ep in
                    guard
                        let numberString = ep["number"],
                        let number = Int(numberString),
                        let href = ep["href"]
                    else { return nil }
                    return EpisodeLink(number: number, title: ep["title"] ?? "", href: href, duration: nil)
                }
            }
            
            DispatchQueue.main.async { completion(resultItems, episodeLinks) }
        }.resume()
    }
    
    // MARK: - Async JS details (Promise-based)
    
    /// Calls the Promise-based JS functions `extractDetails` and `extractEpisodes`
    /// concurrently, waits for both, then delivers results on the main queue.
    func fetchDetailsJS(
        url: String,
        completion: @escaping @Sendable ([MediaItem], [EpisodeLink]) -> Void
    ) {
        guard URL(string: url) != nil else {
            Logger.shared.log("Invalid URL in fetchDetailsJS: \(url)", type: "Error")
            completion([], [])
            return
        }
        
        if let exception = context.exception {
            Logger.shared.log("JavaScript exception before fetchDetailsJS: \(exception)", type: "Error")
            completion([], [])
            return
        }
        
        guard let extractDetailsFunction = context.objectForKeyedSubscript("extractDetails") else {
            Logger.shared.log("JS function extractDetails not found", type: "Error")
            completion([], [])
            return
        }
        
        guard let extractEpisodesFunction = context.objectForKeyedSubscript("extractEpisodes") else {
            Logger.shared.log("JS function extractEpisodes not found", type: "Error")
            completion([], [])
            return
        }
        
        var resultItems: [MediaItem]  = []
        var episodeLinks: [EpisodeLink] = []
        
        let group      = DispatchGroup()
        let resultQueue = DispatchQueue(label: "sora.fetchDetailsJS.results")
        
        group.enter()
        var detailsSettled = false
        
        guard let detailsPromise = extractDetailsFunction.call(withArguments: [url]) else {
            Logger.shared.log("extractDetails did not return a Promise", type: "Error")
            group.leave()
            completion([], [])
            return
        }
        
        let settleDetails: () -> Void = {
            resultQueue.sync {
                guard !detailsSettled else { return }
                detailsSettled = true
                group.leave()
            }
        }
        
        let thenDetails: @convention(block) (JSValue) -> Void = { result in
            defer { settleDetails() }
            guard
                let json = result.toString(),
                let data = json.data(using: .utf8),
                let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                Logger.shared.log("extractDetails: failed to parse JSON response", type: "Error")
                return
            }
            resultQueue.sync {
                resultItems = array.map {
                    MediaItem(
                        description: $0["description"] as? String ?? "",
                        aliases: $0["aliases"] as? String ?? "",
                        airdate: $0["airdate"] as? String ?? ""
                    )
                }
            }
        }
        
        let catchDetails: @convention(block) (JSValue) -> Void = { error in
            Logger.shared.log("extractDetails promise rejected: \(error.toString() ?? "unknown")", type: "Error")
            settleDetails()
        }
        
        detailsPromise.invokeMethod("then",  withArguments: [JSValue(object: thenDetails,  in: context) as Any])
        detailsPromise.invokeMethod("catch", withArguments: [JSValue(object: catchDetails, in: context) as Any])
        
        group.enter()
        var episodesSettled = false
        
        let settleEpisodes: () -> Void = {
            resultQueue.sync {
                guard !episodesSettled else { return }
                episodesSettled = true
                group.leave()
            }
        }
        
        let timeoutItem = DispatchWorkItem { [settleEpisodes] in
            Logger.shared.log("extractEpisodes timed out after 15 s", type: "Warning")
            settleEpisodes()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutItem)
        
        guard let episodesPromise = extractEpisodesFunction.call(withArguments: [url]) else {
            Logger.shared.log("extractEpisodes did not return a Promise", type: "Error")
            timeoutItem.cancel()
            settleEpisodes()
            completion([], [])
            return
        }
        
        let thenEpisodes: @convention(block) (JSValue) -> Void = { result in
            timeoutItem.cancel()
            defer { settleEpisodes() }
            guard
                let json = result.toString(),
                let data = json.data(using: .utf8),
                let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                Logger.shared.log("extractEpisodes: failed to parse JSON response", type: "Error")
                return
            }
            resultQueue.sync {
                episodeLinks = array.map {
                    EpisodeLink(
                        number: $0["number"] as? Int ?? 0,
                        title: "",
                        href: $0["href"] as? String ?? "",
                        duration: nil
                    )
                }
            }
        }
        
        let catchEpisodes: @convention(block) (JSValue) -> Void = { error in
            timeoutItem.cancel()
            Logger.shared.log("extractEpisodes promise rejected: \(error.toString() ?? "unknown")", type: "Error")
            settleEpisodes()
        }
        
        episodesPromise.invokeMethod("then",  withArguments: [JSValue(object: thenEpisodes,  in: context) as Any])
        episodesPromise.invokeMethod("catch", withArguments: [JSValue(object: catchEpisodes, in: context) as Any])
        
        group.notify(queue: .main) {
            completion(resultItems, episodeLinks)
        }
    }
}
