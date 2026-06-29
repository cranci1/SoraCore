//
//  Items.swift
//
//
//  Created by Francesco on 29/06/26.
//

import Foundation

public struct SearchItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let title: String
    public let imageUrl: String
    public let href: String
    
    public init(title: String, imageUrl: String, href: String) {
        self.title = title
        self.imageUrl = imageUrl
        self.href = href
    }
}

public struct MediaItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let description: String
    public let aliases: String
    public let airdate: String
    
    public init(description: String, aliases: String, airdate: String) {
        self.description = description
        self.aliases = aliases
        self.airdate = airdate
    }
}

public struct EpisodeLink: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let number: Int
    public let title: String
    public let href: String
    public let duration: Int?
    
    public init(number: Int, title: String, href: String, duration: Int?) {
        self.number = number
        self.title = title
        self.href = href
        self.duration = duration
    }
}
