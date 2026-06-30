//
//  ServiceSearch.swift
//
//
//  Created by Francesco on 30/06/26.
//

import Foundation
import Sybau

extension ServiceManager {
    public func searchInActiveServicesProgressively(
        query: String,
        onResult: @escaping @Sendable (Service, [SearchItem]?) -> Void,
        onComplete: @escaping @Sendable () -> Void
    ) async {
        let services = activeServices
        
        guard !services.isEmpty else {
            onComplete()
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask {
                    let results = await Self.search(service, query: query)
                    onResult(service, results)
                }
            }
            await group.waitForAll()
        }
        
        onComplete()
    }
    
    private nonisolated static func search(_ service: Service, query: String) async -> [SearchItem]? {
        let script = service.jsScript
        guard !script.isEmpty else {
            Logger.shared.log("Empty JS script for module: \(service.metadata.sourceName)", type: "Error")
            return nil
        }
        
        let controller = JSController()
        controller.loadScript(script)
        
        return await withCheckedContinuation { continuation in
            if service.metadata.isAsyncJS {
                controller.fetchJsSearchResults(keyword: query, module: service) { items in
                    continuation.resume(returning: items)
                }
            } else {
                controller.fetchSearchResults(keyword: query, module: service) { items in
                    continuation.resume(returning: items)
                }
            }
        }
    }
}
