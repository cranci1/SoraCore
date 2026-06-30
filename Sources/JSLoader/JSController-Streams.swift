//
//  JSController-Streams.swift
//  Sulfur
//
//  Created by Francesco on 30/03/25.
//

import Sybau
import JavaScriptCore

public typealias StreamResult = (streams: [String]?, subtitles: [String]?, sources: [[String: Any]]?)

extension JSController {
    // MARK: HTML-based stream extraction (synchronous JS)
    
    /// Fetches the page at `episodeUrl`, then passes the HTML to the synchronous JS
    /// function `extractStreamUrl`
    public func fetchStreamUrl(
        episodeUrl: String,
        softsub: Bool = false,
        module: Service,
        completion: @escaping @Sendable (StreamResult) -> Void
    ) {
        guard let url = URL(string: episodeUrl) else {
            completion((nil, nil, nil))
            return
        }
        
        URLSession.custom.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            
            if let error {
                Logger.shared.log("fetchStreamUrl network error: \(error)", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let data, let html = String(data: data, encoding: .utf8) else {
                Logger.shared.log("fetchStreamUrl: failed to decode HTML", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            Logger.shared.log(html, type: "HTMLStrings")
            
            guard let fn = self.context.objectForKeyedSubscript("extractStreamUrl") else {
                Logger.shared.log("extractStreamUrl function not found in JS context", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            let result = fn.call(withArguments: [html])
            
            if let ex = self.context.exception {
                Logger.shared.log("JS exception in extractStreamUrl: \(ex)", type: "Error")
                self.context.exception = nil
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let result, !result.isNull, !result.isUndefined else {
                Logger.shared.log("extractStreamUrl returned null/undefined", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let resultString = result.toString(), resultString != "[object Promise]" else {
                Logger.shared.log("extractStreamUrl returned a Promise instead of a value", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            let parsed = Self.parseStreamResult(resultString)
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }
    
    // MARK: Promise-based stream extraction (async JS, URL passed directly)
    
    /// Calls `extractStreamUrl(episodeUrl)` as a Promise-returning JS function
    public func fetchStreamUrlJS(
        episodeUrl: String,
        softsub: Bool = false,
        module: Service,
        completion: @escaping @Sendable (StreamResult) -> Void
    ) {
        guard preflightContext(for: "extractStreamUrl", completion: completion) else { return }
        
        let fn = context.objectForKeyedSubscript("extractStreamUrl")!
        guard let promise = fn.call(withArguments: [episodeUrl]) else {
            Logger.shared.log("extractStreamUrl did not return a Promise", type: "Error")
            completion((nil, nil, nil))
            return
        }
        
        attachStreamPromiseHandlers(promise: promise, completion: completion)
    }
    
    // MARK: Promise-based stream extraction (async JS, HTML fetched first)
    
    /// Fetches the page at `episodeUrl` over URLSession, then calls
    /// `extractStreamUrl(html)` as a Promise-returning JS function
    public func fetchStreamUrlJSSecond(
        episodeUrl: String,
        softsub: Bool = false,
        module: Service,
        completion: @escaping @Sendable (StreamResult) -> Void
    ) {
        guard let url = URL(string: episodeUrl) else {
            completion((nil, nil, nil))
            return
        }
        
        URLSession.custom.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            
            if let error {
                Logger.shared.log("fetchStreamUrlJSSecond network error: \(error.localizedDescription)", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let data, let html = String(data: data, encoding: .utf8) else {
                Logger.shared.log("fetchStreamUrlJSSecond: failed to decode HTML", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            DispatchQueue.main.async {
                guard self.preflightContext(for: "extractStreamUrl", completion: completion) else { return }
                
                let fn = self.context.objectForKeyedSubscript("extractStreamUrl")!
                guard let promise = fn.call(withArguments: [html]) else {
                    Logger.shared.log("extractStreamUrl did not return a Promise", type: "Error")
                    completion((nil, nil, nil))
                    return
                }
                
                self.attachStreamPromiseHandlers(promise: promise, completion: completion)
            }
        }.resume()
    }
    
    // MARK: - Shared helpers
    
    private func preflightContext(
        for functionName: String,
        completion: @escaping @Sendable (StreamResult) -> Void
    ) -> Bool {
        if let ex = context.exception {
            Logger.shared.log("JS exception before \(functionName): \(ex)", type: "Error")
            completion((nil, nil, nil))
            return false
        }
        guard context.objectForKeyedSubscript(functionName) != nil else {
            Logger.shared.log("\(functionName) function not found in JS context", type: "Error")
            completion((nil, nil, nil))
            return false
        }
        return true
    }
    
    private func attachStreamPromiseHandlers(
        promise: JSValue,
        completion: @escaping @Sendable (StreamResult) -> Void
    ) {
        let thenBlock: @convention(block) (JSValue) -> Void = { result in
            if result.isNull || result.isUndefined {
                Logger.shared.log("Stream Promise resolved to null/undefined", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            guard let json = result.toString(), json != "[object Promise]" else {
                Logger.shared.log("Stream Promise resolved to a nested Promise", type: "Stream")
                return
            }
            let parsed = Self.parseStreamResult(json)
            DispatchQueue.main.async { completion(parsed) }
        }
        
        let catchBlock: @convention(block) (JSValue) -> Void = { error in
            Logger.shared.log("Stream Promise rejected: \(error.toString() ?? "unknown")", type: "Error")
            DispatchQueue.main.async { completion((nil, nil, nil)) }
        }
        
        guard
            let thenFn  = JSValue(object: thenBlock,  in: context),
            let catchFn = JSValue(object: catchBlock, in: context)
        else {
            Logger.shared.log("Failed to create JSValue callbacks for stream Promise", type: "Error")
            completion((nil, nil, nil))
            return
        }
        
        promise.invokeMethod("then",  withArguments: [thenFn])
        promise.invokeMethod("catch", withArguments: [catchFn])
    }
    
    /// Parses the JSON string returned by `extractStreamUrl` into a `StreamResult`.
    ///
    /// Supported shapes:
    /// - `{ "stream": "url" | { url, headers }, "streams": [...], "subtitles": "url" | [...] }`
    /// - `["url1", "url2"]`
    /// - A bare URL string.
    private static func parseStreamResult(_ jsonString: String) -> StreamResult {
        guard let data = jsonString.data(using: .utf8) else {
            Logger.shared.log("parseStreamResult: failed to encode JSON string", type: "Error")
            return ([jsonString], nil, nil)
        }
        
        do {
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var streams: [String]? = nil
                var subtitles: [String]? = nil
                var sources: [[String: Any]]? = nil
                
                if let arr = obj["streams"] as? [[String: Any]] {
                    sources = arr
                    Logger.shared.log("Found \(arr.count) streams with headers", type: "Stream")
                } else if let single = obj["stream"] as? [String: Any] {
                    sources = [single]
                    Logger.shared.log("Found 1 stream with headers", type: "Stream")
                } else if let arr = obj["streams"] as? [String] {
                    streams = arr
                    Logger.shared.log("Found \(arr.count) streams", type: "Stream")
                } else if let single = obj["stream"] as? String {
                    streams = [single]
                    Logger.shared.log("Found 1 stream", type: "Stream")
                }
                
                if let arr = obj["subtitles"] as? [String] {
                    subtitles = arr
                    Logger.shared.log("Found \(arr.count) subtitle tracks", type: "Stream")
                } else if let single = obj["subtitles"] as? String {
                    subtitles = [single]
                    Logger.shared.log("Found 1 subtitle track", type: "Stream")
                }
                
                Logger.shared.log(
                    "Stream result: \(streams?.count ?? sources?.count ?? 0) source(s), " +
                    "\(subtitles?.count ?? 0) subtitle(s)",
                    type: "Stream"
                )
                return (streams, subtitles, sources)
            }
            
            if let arr = try JSONSerialization.jsonObject(with: data) as? [String] {
                Logger.shared.log("Found \(arr.count) stream URLs (array form)", type: "Stream")
                return (arr, nil, nil)
            }
        } catch {
            Logger.shared.log("parseStreamResult JSON error: \(error.localizedDescription)", type: "Error")
        }
        
        Logger.shared.log("Using raw string as stream URL", type: "Stream")
        return ([jsonString], nil, nil)
    }
}
