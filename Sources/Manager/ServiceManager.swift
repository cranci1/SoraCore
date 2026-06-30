//
//  ModuleManager.swift
//  Sora
//
//  Created by Francesco on 26/01/25.
//

import Sybau
import Foundation

extension Notification.Name {
    static let servicesSyncDidComplete = Notification.Name("servicesSyncDidComplete")
    static let moduleRemoved = Notification.Name("moduleRemoved")
    static let didReceiveNewModule = Notification.Name("didReceiveNewModule")
    static let didUpdateservices = Notification.Name("didUpdateservices")
}

@MainActor
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()
    
    @Published public var services: [Service] = []
    @Published public var selectedModuleChanged = false
    
    public var activeServices: [Service] { services.filter { $0.isActive } }
    
    private let fileManager = FileManager.default
    private let servicesFileName = "services.json"
    
    public init() {
        let url = getservicesFilePath()
        if (!FileManager.default.fileExists(atPath: url.path)) {
            do {
                try "[]".write(to: url, atomically: true, encoding: .utf8)
                Logger.shared.log("Created empty services file", type: "Info")
            } catch {
                Logger.shared.log("Failed to create services file: \(error.localizedDescription)", type: "Error")
            }
        }
        loadservices()
        NotificationCenter.default.addObserver(self, selector: #selector(handleservicesSyncCompleted), name: .servicesSyncDidComplete, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleservicesSyncCompleted() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let url = self.getservicesFilePath()
            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.shared.log("No services file found after sync", type: "Error")
                self.services = []
                return
            }
            
            do {
                let data = try Data(contentsOf: url)
                let decodedservices = try JSONDecoder().decode([Service].self, from: data)
                self.services = decodedservices
                
                Task {
                    await self.checkJSModuleFiles()
                }
                Logger.shared.log("Reloaded services after iCloud sync")
            } catch {
                Logger.shared.log("Error handling services sync: \(error.localizedDescription)", type: "Error")
                self.services = []
            }
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getservicesFilePath() -> URL {
        getDocumentsDirectory().appendingPathComponent(servicesFileName)
    }
    
    public func loadservices() {
        let url = getservicesFilePath()
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.shared.log("services file does not exist, creating empty one", type: "Info")
            do {
                try "[]".write(to: url, atomically: true, encoding: .utf8)
                services = []
            } catch {
                Logger.shared.log("Failed to create services file: \(error.localizedDescription)", type: "Error")
                services = []
            }
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            do {
                let decodedservices = try JSONDecoder().decode([Service].self, from: data)
                services = decodedservices
                
                Task {
                    await checkJSModuleFiles()
                }
            } catch {
                Logger.shared.log("Failed to decode services: \(error.localizedDescription)", type: "Error")
                try "[]".write(to: url, atomically: true, encoding: .utf8)
                services = []
            }
        } catch {
            Logger.shared.log("Failed to load services file: \(error.localizedDescription)", type: "Error")
            services = []
        }
    }
    
    public func checkJSModuleFiles() async {
        Logger.shared.log("Checking JS module files...", type: "Info")
        var missingCount = 0
        
        for module in services {
            let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
            if !fileManager.fileExists(atPath: localUrl.path) {
                missingCount += 1
                do {
                    guard let scriptUrl = URL(string: module.metadata.scriptUrl) else {
                        Logger.shared.log("Invalid script URL for module: \(module.metadata.sourceName)", type: "Error")
                        continue
                    }
                    
                    Logger.shared.log("Downloading missing JS file for: \(module.metadata.sourceName)", type: "Info")
                    
                    let (scriptData, _) = try await URLSession.custom.data(from: scriptUrl)
                    guard let jsContent = String(data: scriptData, encoding: .utf8) else {
                        Logger.shared.log("Invalid script encoding for module: \(module.metadata.sourceName)", type: "Error")
                        continue
                    }
                    
                    try jsContent.write(to: localUrl, atomically: true, encoding: .utf8)
                    Logger.shared.log("Successfully downloaded JS file for module: \(module.metadata.sourceName)")
                } catch {
                    Logger.shared.log("Failed to download JS file for module: \(module.metadata.sourceName) - \(error.localizedDescription)", type: "Error")
                }
            }
        }
        
        if missingCount > 0 {
            Logger.shared.log("Downloaded \(missingCount) missing module JS files", type: "Info")
        } else {
            Logger.shared.log("All module JS files are present", type: "Info")
        }
    }
    
    private func saveservices() {
        DispatchQueue.main.async {
            let url = self.getservicesFilePath()
            guard let data = try? JSONEncoder().encode(self.services) else { return }
            try? data.write(to: url)
        }
    }
    
    public func addModule(metadataUrl: String) async throws -> Service {
        guard let url = URL(string: metadataUrl) else {
            throw NSError(domain: "Invalid metadata URL", code: -1)
        }
        
        if services.contains(where: { $0.metadataUrl == metadataUrl }) {
            throw NSError(domain: "Module already exists", code: -1)
        }
        
        let (metadataData, _) = try await URLSession.custom.data(from: url)
        let metadata = try JSONDecoder().decode(ServiceMetadata.self, from: metadataData)
        
        guard let scriptUrl = URL(string: metadata.scriptUrl) else {
            throw NSError(domain: "Invalid script URL", code: -1)
        }
        
        let (scriptData, _) = try await URLSession.custom.data(from: scriptUrl)
        guard let jsContent = String(data: scriptData, encoding: .utf8) else {
            throw NSError(domain: "Invalid script encoding", code: -1)
        }
        
        let fileName = "\(UUID().uuidString).js"
        let localUrl = getDocumentsDirectory().appendingPathComponent(fileName)
        try jsContent.write(to: localUrl, atomically: true, encoding: .utf8)
        
        let module = Service(
            metadata: metadata,
            localPath: fileName,
            metadataUrl: metadataUrl
        )
        
        DispatchQueue.main.async {
            self.services.append(module)
            self.saveservices()
            self.selectedModuleChanged = true
            Logger.shared.log("Added module: \(module.metadata.sourceName)")
        }
        
        return module
    }
    
    public func deleteModule(_ module: Service) {
        let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
        try? fileManager.removeItem(at: localUrl)
        
        services.removeAll { $0.id == module.id }
        saveservices()
        Logger.shared.log("Deleted module: \(module.metadata.sourceName)")
        
        NotificationCenter.default.post(name: .moduleRemoved, object: module.id.uuidString)
    }
    
    public func removeService(_ service: Service) {
        deleteModule(service)
    }
    
    public func setServiceState(_ service: Service, isActive: Bool) {
        guard let index = services.firstIndex(where: { $0.id == service.id }) else { return }
        services[index].isActive = isActive
        saveservices()
        selectedModuleChanged = true
    }
    
    public func moveServices(fromOffsets indices: IndexSet, toOffset offset: Int) {
        services.move(fromOffsets: indices, toOffset: offset)
        saveservices()
    }
    
    public func handlePotentialServiceURL(_ urlString: String) async -> Bool {
        do {
            _ = try await addModule(metadataUrl: urlString)
            return true
        } catch {
            Logger.shared.log("Failed to add service from URL: \(error.localizedDescription)", type: "Error")
            return false
        }
    }
    
    public func getModuleContent(_ module: Service) throws -> String {
        let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
        return try String(contentsOf: localUrl, encoding: .utf8)
    }
    
    public func updateServices() async {
        let servicesCopy = services
        var updatedservices: [(Int, Service)] = []
        
        for (index, module) in servicesCopy.enumerated() {
            do {
                guard let metadataUrl = URL(string: module.metadataUrl) else {
                    Logger.shared.log("Invalid metadata URL for module: \(module.metadata.sourceName)", type: "Error")
                    continue
                }
                
                let (metadataData, _) = try await URLSession.custom.data(from: metadataUrl)
                let newMetadata = try JSONDecoder().decode(ServiceMetadata.self, from: metadataData)
                
                if newMetadata.version != module.metadata.version {
                    guard let scriptUrl = URL(string: newMetadata.scriptUrl) else {
                        throw NSError(domain: "Invalid script URL", code: -1)
                    }
                    
                    let (scriptData, _) = try await URLSession.custom.data(from: scriptUrl)
                    guard let jsContent = String(data: scriptData, encoding: .utf8) else {
                        throw NSError(domain: "Invalid script encoding", code: -1)
                    }
                    
                    let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
                    try jsContent.write(to: localUrl, atomically: true, encoding: .utf8)
                    
                    let updatedModule = Service(
                        id: module.id,
                        metadata: newMetadata,
                        localPath: module.localPath,
                        metadataUrl: module.metadataUrl,
                        isActive: module.isActive
                    )
                    
                    updatedservices.append((index, updatedModule))
                    Logger.shared.log("Prepared update for module: \(module.metadata.sourceName) to version \(newMetadata.version)")
                }
            } catch {
                Logger.shared.log("Failed to refresh module: \(module.metadata.sourceName) - \(error.localizedDescription)")
            }
        }
        
        if !updatedservices.isEmpty {
            for (index, updatedModule) in updatedservices {
                if index < services.count {
                    services[index] = updatedModule
                }
            }
            saveservices()
            Logger.shared.log("Successfully updated \(updatedservices.count) services")
        }
    }
}
