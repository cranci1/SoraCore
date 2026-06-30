//
//  JSController.swift
//  Sora
//
//  Created by Francesco on 05/01/25.
//

import Sybau
import JavaScriptCore

final class JSController: NSObject, ObservableObject {
    public static let shared = JSController()
    private(set) var context: JSContext
    
    // MARK: - Init
    
    public override init() {
        self.context = JSContext()
        super.init()
        setupContext()
    }
    
    // MARK: - Context lifecycle
    
    private func setupContext() {
        context.setupJavaScriptEnvironment()
        context.exceptionHandler = { _, exception in
            Logger.shared.log("[JS Exception] \(exception?.toString() ?? "unknown")", type: "Error")
        }
    }
    
    public func loadScript(_ script: String) {
        context = JSContext()
        setupContext()
        context.evaluateScript(script)
        
        if let exception = context.exception {
            Logger.shared.log("Error loading script: \(exception)", type: "Error")
        }
    }
}
