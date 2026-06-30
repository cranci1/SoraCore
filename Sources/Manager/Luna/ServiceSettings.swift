//
//  ServiceSettings.swift
//
//
//  Created by Francesco on 30/06/26.
//

import Sybau
import Foundation

public struct ServiceSetting: Identifiable, Hashable, Sendable {
    public enum SettingType: String, Codable, Sendable {
        case string, bool, int, float
    }
    
    public var id: String { key }
    public let key: String
    public var value: String
    public let type: SettingType
    public let comment: String?
    public let options: [String]?
    
    public init(key: String, value: String, type: SettingType, comment: String? = nil, options: [String]? = nil) {
        self.key = key
        self.value = value
        self.type = type
        self.comment = comment
        self.options = options
    }
}

private struct ServiceSettingSchemaEntry: Codable {
    let key: String
    let type: String
    let comment: String?
    let defaultValue: String?
    let options: [String]?
    
    enum CodingKeys: String, CodingKey {
        case key, type, comment, options
        case defaultValue = "default"
    }
}

extension ServiceManager {
    public func getServiceSettings(_ service: Service) -> [ServiceSetting] {
        let schema = Self.parseSettingsSchema(from: service.jsScript)
        let overrides = loadSettingOverrides(for: service)
        
        return schema.map { entry in
            let type = ServiceSetting.SettingType(rawValue: entry.type.lowercased()) ?? .string
            let storedValue = overrides[entry.key] ?? entry.defaultValue ?? ""
            return ServiceSetting(
                key: entry.key,
                value: storedValue,
                type: type,
                comment: entry.comment,
                options: entry.options
            )
        }
    }
    
    @discardableResult
    public func updateServiceSettings(_ service: Service, settings: [ServiceSetting]) -> Bool {
        var overrides: [String: String] = [:]
        for setting in settings {
            overrides[setting.key] = setting.value
        }
        
        guard let data = try? JSONEncoder().encode(overrides) else {
            Logger.shared.log("Failed to encode settings for module: \(service.metadata.sourceName)", type: "Error")
            return false
        }
        
        UserDefaults.standard.set(data, forKey: settingsStorageKey(for: service))
        Logger.shared.log("Updated settings for module: \(service.metadata.sourceName)")
        return true
    }
    
    private func settingsStorageKey(for service: Service) -> String {
        "serviceSettings_\(service.id.uuidString)"
    }
    
    private func loadSettingOverrides(for service: Service) -> [String: String] {
        guard
            let data = UserDefaults.standard.data(forKey: settingsStorageKey(for: service)),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
    
    private static func parseSettingsSchema(from script: String) -> [ServiceSettingSchemaEntry] {
        guard
            let markerRange = script.range(of: "SETTINGS_SCHEMA:"),
            let lineEnd = script[markerRange.upperBound...].firstIndex(of: "\n")
        else { return [] }
        
        let jsonString = String(script[markerRange.upperBound..<lineEnd]).trimmingCharacters(in: .whitespaces)
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        do {
            return try JSONDecoder().decode([ServiceSettingSchemaEntry].self, from: data)
        } catch {
            Logger.shared.log("Failed to parse SETTINGS_SCHEMA: \(error.localizedDescription)", type: "Error")
            return []
        }
    }
}
