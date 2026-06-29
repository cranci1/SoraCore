//
//  Services.swift
//
//
//  Created by Francesco on 29/06/26.
//

import Foundation

struct Service: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let metadata: ServiceMetadata
    let localPath: String
    let metadataUrl: String
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        metadata: ServiceMetadata,
        localPath: String,
        metadataUrl: String,
        isActive: Bool = false
    ) {
        self.id = id
        self.metadata = metadata
        self.localPath = localPath
        self.metadataUrl = metadataUrl
        self.isActive = isActive
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Service, rhs: Service) -> Bool {
        lhs.id == rhs.id
    }
}

struct ServiceMetadata: Codable, Hashable, Sendable {
    let sourceName: String
    let author: Author
    let iconUrl: String
    let version: String
    let language: String
    let baseUrl: String
    let streamType: String
    let quality: String
    let searchBaseUrl: String
    let scriptUrl: String
    
    // Optional feature flags
    let asyncJS: Bool?
    let streamAsyncJS: Bool?
    let softsub: Bool?
    let multiStream: Bool?
    let multiSubs: Bool?
    let type: String?
    
    // Convenience helpers so call-sites don't need to `?? false` everywhere
    var isAsyncJS: Bool         { asyncJS       ?? false }
    var isStreamAsyncJS: Bool   { streamAsyncJS ?? false }
    var hasSoftsub: Bool        { softsub       ?? false }
    var hasMultiStream: Bool    { multiStream   ?? false }
    var hasMultiSubs: Bool      { multiSubs     ?? false }
    
    struct Author: Codable, Hashable, Sendable {
        let name: String
        let icon: String
    }
}
