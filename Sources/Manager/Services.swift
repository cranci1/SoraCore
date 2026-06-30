//
//  Services.swift
//
//
//  Created by Francesco on 29/06/26.
//

import Foundation

public struct Service: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let metadata: ServiceMetadata
    public let localPath: String
    public let metadataUrl: String
    public var isActive: Bool
    
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
    
    public var url: String { metadataUrl }
    
    public var jsScript: String {
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localUrl = documentsUrl.appendingPathComponent(localPath)
        return (try? String(contentsOf: localUrl, encoding: .utf8)) ?? ""
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Service, rhs: Service) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ServiceMetadata: Codable, Hashable, Sendable {
    public let sourceName: String
    public let author: Author
    public let iconUrl: String
    public let version: String
    public let language: String
    public let baseUrl: String
    public let streamType: String
    public let quality: String
    public let searchBaseUrl: String
    public let scriptUrl: String
    
    public let asyncJS: Bool?
    public let streamAsyncJS: Bool?
    public let softsub: Bool?
    public let multiStream: Bool?
    public let multiSubs: Bool?
    public let type: String?
    public let settings: Bool?
    
    public var isAsyncJS: Bool { asyncJS ?? false }
    public var isStreamAsyncJS: Bool { streamAsyncJS ?? false }
    public var hasSoftsub: Bool { softsub ?? false }
    public var hasMultiStream: Bool { multiStream ?? false }
    public var hasMultiSubs: Bool { multiSubs ?? false }
    
    public struct Author: Codable, Hashable, Sendable {
        public let name: String
        public let icon: String
    }
}
