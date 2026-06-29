//
//  JSController-Search.swift
//  Sulfur
//
//  Created by Francesco on 30/03/25.
//

import Sybau
import JavaScriptCore

extension JSController {
    
    // MARK: - HTML-based search (synchronous JS)
    
    /// Fetches a search page, then passes the raw HTML to the JS `searchResults` function.
    func fetchSearchResults(
        keyword: String,
        module: Service,
        completion: @escaping @Sendable ([SearchItem]) -> Void
    ) {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let searchUrl = module.metadata.searchBaseUrl.replacingOccurrences(of: "%s", with: encodedKeyword)
        
        guard let url = URL(string: searchUrl) else {
            Logger.shared.log("Invalid search URL: \(searchUrl)", type: "Error")
            completion([])
            return
        }
        
        URLSession.custom.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            
            if let error {
                Logger.shared.log("Network error while searching: \(error)", type: "Error")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            guard let data, let html = String(data: data, encoding: .utf8) else {
                Logger.shared.log("Could not decode HTML response", type: "Error")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            Logger.shared.log(html, type: "HTMLStrings")
            
            guard
                let parseFunction = self.context.objectForKeyedSubscript("searchResults"),
                let rawResults = parseFunction.call(withArguments: [html]).toArray() as? [[String: String]]
            else {
                Logger.shared.log("Could not parse search results", type: "Error")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            let items = rawResults.map {
                SearchItem(title: $0["title"] ?? "", imageUrl: $0["image"] ?? "", href: $0["href"] ?? "")
            }
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }
    
    // MARK: - Async JS search (Promise-based)
    
    /// Calls the JS `searchResults` function directly (no prior HTTP fetch) and awaits
    /// its Promise.  Used for modules with `asyncJS == true`.
    func fetchJsSearchResults(
        keyword: String,
        module: Service,
        completion: @escaping @Sendable ([SearchItem]) -> Void
    ) {
        if let exception = context.exception {
            Logger.shared.log("JavaScript exception before search: \(exception)", type: "Error")
            completion([])
            return
        }
        
        guard let searchFunction = context.objectForKeyedSubscript("searchResults") else {
            Logger.shared.log("searchResults function not found in module", type: "Error")
            completion([])
            return
        }
        
        guard let promise = searchFunction.call(withArguments: [keyword]) else {
            Logger.shared.log("searchResults returned nil", type: "Error")
            completion([])
            return
        }
        
        let thenBlock: @convention(block) (JSValue) -> Void = { result in
            Logger.shared.log(result.toString() ?? "", type: "HTMLStrings")
            
            guard
                let jsonString = result.toString(),
                let data = jsonString.data(using: .utf8)
            else {
                Logger.shared.log("Invalid search result format", type: "Error")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    Logger.shared.log("Search result is not a JSON array", type: "Error")
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                let items: [SearchItem] = array.compactMap { item in
                    guard
                        let title = item["title"] as? String,
                        let imageUrl = item["image"] as? String,
                        let href = item["href"] as? String
                    else {
                        Logger.shared.log("Skipping malformed search result: \(item)", type: "Error")
                        return nil
                    }
                    return SearchItem(title: title, imageUrl: imageUrl, href: href)
                }
                
                DispatchQueue.main.async { completion(items) }
            } catch {
                Logger.shared.log("JSON parsing error in search: \(error)", type: "Error")
                DispatchQueue.main.async { completion([]) }
            }
        }
        
        let catchBlock: @convention(block) (JSValue) -> Void = { error in
            Logger.shared.log("Search promise rejected: \(error.toString() ?? "unknown")", type: "Error")
            DispatchQueue.main.async { completion([]) }
        }
        
        promise.invokeMethod("then", withArguments: [JSValue(object: thenBlock,  in: context) as Any])
        promise.invokeMethod("catch", withArguments: [JSValue(object: catchBlock, in: context) as Any])
    }
}
