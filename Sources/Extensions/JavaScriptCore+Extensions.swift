//
//  JavaScriptCore_Extensions.swift
//  Sora
//
//  Created by Hamzo on 19/03/25.
//

import Sybau
import JavaScriptCore

extension JSContext {
    
    // MARK: - console.log / console.error
    
    func setupConsoleLogging() {
        guard let consoleObject = JSValue(newObjectIn: self) else { return }
        
        let logFn: @convention(block) (String) -> Void = { message in
            Logger.shared.log(message, type: "Debug")
        }
        let errorFn: @convention(block) (String) -> Void = { message in
            Logger.shared.log(message, type: "Error")
        }
        
        consoleObject.setObject(logFn,   forKeyedSubscript: "log"   as NSString)
        consoleObject.setObject(errorFn, forKeyedSubscript: "error" as NSString)
        setObject(consoleObject, forKeyedSubscript: "console" as NSString)
        
        setObject(logFn, forKeyedSubscript: "log" as NSString)
    }
    
    // MARK: - fetch (v1)
    
    func setupNativeFetch() {
        let fetchNative: @convention(block) (String, [String: String]?, JSValue, JSValue) -> Void = {
            urlString, headers, resolve, reject in
            
            guard let url = URL(string: urlString) else {
                Logger.shared.log("fetchNative: invalid URL '\(urlString)'", type: "Error")
                reject.call(withArguments: ["Invalid URL"])
                return
            }
            
            var request = URLRequest(url: url)
            headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            URLSession.custom.dataTask(with: request) { data, _, error in
                if let error {
                    Logger.shared.log("fetchNative network error: \(error.localizedDescription)", type: "Error")
                    reject.call(withArguments: [error.localizedDescription])
                    return
                }
                guard let data else {
                    Logger.shared.log("fetchNative: no data in response", type: "Error")
                    reject.call(withArguments: ["No data"])
                    return
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    Logger.shared.log("fetchNative: unable to decode response as UTF-8", type: "Error")
                    reject.call(withArguments: ["Unable to decode data"])
                    return
                }
                resolve.call(withArguments: [text])
            }.resume()
        }
        
        setObject(fetchNative, forKeyedSubscript: "fetchNative" as NSString)
        evaluateScript("""
            function fetch(url, headers) {
                return new Promise(function(resolve, reject) {
                    fetchNative(url, headers, resolve, reject);
                });
            }
            """)
    }
    
    // MARK: - fetchv2 (method, body, redirect, encoding, response object)
    
    func setupFetchV2() {
        let fetchV2Native: @convention(block) (String, Any?, String?, String?, ObjCBool, String?, JSValue, JSValue) -> Void = {
            urlString, headersAny, method, body, redirect, encoding, resolve, reject in
            
            let callResolve: ([String: Any]) -> Void = { dict in
                DispatchQueue.main.async {
                    guard !resolve.isUndefined else {
                        Logger.shared.log("fetchV2: resolve callback is undefined", type: "Error")
                        return
                    }
                    resolve.call(withArguments: [dict])
                }
            }
            
            guard let url = URL(string: urlString) else {
                Logger.shared.log("fetchV2: invalid URL '\(urlString)'", type: "Error")
                callResolve(["error": "Invalid URL"])
                return
            }
            
            var headers: [String: String] = [:]
            if let raw = headersAny, !(raw is NSNull) {
                func toString(_ v: Any) -> String? {
                    if let s = v as? String { return s }
                    if let n = v as? NSNumber { return n.stringValue }
                    if v is NSNull { return nil }
                    return String(describing: v)
                }
                if let dict = raw as? [String: Any] {
                    for (k, v) in dict { if let s = toString(v) { headers[k] = s } }
                } else if let dict = raw as? [AnyHashable: Any] {
                    for (k, v) in dict { if let s = toString(v) { headers[String(describing: k)] = s } }
                } else {
                    Logger.shared.log("fetchV2: headers type \(type(of: raw)) ignored", type: "Warning")
                }
            }
            
            func resolveEncoding(_ name: String?) -> String.Encoding {
                switch name?.lowercased() {
                case "utf-8", "utf8": return .utf8
                case "windows-1251", "cp1251": return .windowsCP1251
                case "windows-1252", "cp1252": return .windowsCP1252
                case "iso-8859-1", "latin1": return .isoLatin1
                case "ascii": return .ascii
                case "utf-16", "utf16": return .utf16
                default:
                    if let name { Logger.shared.log("fetchV2: unknown encoding '\(name)', using UTF-8", type: "Warning") }
                    return .utf8
                }
            }
            
            let httpMethod = method ?? "GET"
            let textEncoding = resolveEncoding(encoding)
            let bodyIsEmpty = body == nil || body?.isEmpty == true || body == "null" || body == "undefined"
            
            if httpMethod == "GET" && !bodyIsEmpty {
                Logger.shared.log("fetchV2: GET request must not have a body", type: "Error")
                callResolve(["error": "GET request must not have a body"])
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if httpMethod != "GET", !bodyIsEmpty, let bodyString = body {
                request.httpBody = bodyString.data(using: .utf8)
            }
            
            let session = URLSession.fetchData(allowRedirects: redirect.boolValue)
            
            session.downloadTask(with: request) { tempURL, response, error in
                defer { session.finishTasksAndInvalidate() }
                
                if let error {
                    Logger.shared.log("fetchV2 network error: \(error.localizedDescription)", type: "Error")
                    callResolve(["error": error.localizedDescription])
                    return
                }
                guard let tempURL else {
                    Logger.shared.log("fetchV2: no data in response", type: "Error")
                    callResolve(["error": "No data"])
                    return
                }
                
                var safeHeaders: [String: String] = [:]
                if let http = response as? HTTPURLResponse {
                    for (k, v) in http.allHeaderFields {
                        if let key = k as? String {
                            safeHeaders[key] = (v as? String) ?? String(describing: v)
                        }
                    }
                }
                
                var responseDict: [String: Any] = [
                    "status":  (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "headers": safeHeaders,
                    "body":    "",
                ]
                
                do {
                    let data = try Data(contentsOf: tempURL)
                    guard data.count <= 10_000_000 else {
                        Logger.shared.log("fetchV2: response exceeds 10 MB limit", type: "Error")
                        callResolve(["error": "Response exceeds maximum size"])
                        return
                    }
                    
                    if let text = String(data: data, encoding: textEncoding) {
                        responseDict["body"] = text
                    } else {
                        Logger.shared.log("fetchV2: \(encoding ?? "utf-8") decode failed, trying UTF-8", type: "Warning")
                        responseDict["body"] = String(data: data, encoding: .utf8) ?? ""
                    }
                    callResolve(responseDict)
                } catch {
                    Logger.shared.log("fetchV2: error reading temp file: \(error.localizedDescription)", type: "Error")
                    callResolve(["error": "Error reading downloaded file"])
                }
            }.resume()
        }
        
        setObject(fetchV2Native, forKeyedSubscript: "fetchV2Native" as NSString)
        evaluateScript("""
            function fetchv2(url, headers = {}, method = "GET", body = null, redirect = true, encoding) {
                var processedBody = (method !== "GET" && body && typeof body === 'object')
                    ? JSON.stringify(body)
                    : (method !== "GET" ? body : null);
            
                var processedHeaders = (headers && typeof headers === 'object' && !Array.isArray(headers))
                    ? headers : {};
            
                var finalEncoding = encoding || "utf-8";
            
                return new Promise(function(resolve, reject) {
                    fetchV2Native(url, processedHeaders, method, processedBody, redirect, finalEncoding,
                        function(rawText) {
                            resolve({
                                headers: rawText.headers,
                                status:  rawText.status,
                                _data:   rawText.body,
                                text: function() { return Promise.resolve(this._data); },
                                json: function() {
                                    try   { return Promise.resolve(JSON.parse(this._data)); }
                                    catch (e) { return Promise.reject("JSON parse error: " + e.message); }
                                }
                            });
                        },
                        reject
                    );
                });
            }
            """)
    }
    
    // MARK: - btoa / atob
    
    func setupBase64Functions() {
        let btoaFn: @convention(block) (String) -> String? = { data in
            guard let bytes = data.data(using: .utf8) else {
                Logger.shared.log("btoa: input is not valid UTF-8", type: "Error")
                return nil
            }
            return bytes.base64EncodedString()
        }
        
        let atobFn: @convention(block) (String) -> String? = { base64 in
            guard let bytes = Data(base64Encoded: base64) else {
                Logger.shared.log("atob: input is not valid base64", type: "Error")
                return nil
            }
            return String(data: bytes, encoding: .utf8)
        }
        
        setObject(btoaFn, forKeyedSubscript: "btoa" as NSString)
        setObject(atobFn, forKeyedSubscript: "atob" as NSString)
    }
    
    // MARK: - Utilities
    
    func setupUtilities() {
        evaluateScript("""
            function getElementsByTag(html, tag) {
                const re = new RegExp('<' + tag + '[^>]*>([\\\\s\\\\S]*?)<\\\\/' + tag + '>', 'gi');
                const out = [];
                let m;
                while ((m = re.exec(html)) !== null) out.push(m[1]);
                return out;
            }
            function getAttribute(html, tag, attr) {
                const re = new RegExp('<' + tag + '[^>]*' + attr + '=[\\\"\\']?([^\\\"\\'> ]+)', 'i');
                const m = re.exec(html);
                return m ? m[1] : null;
            }
            function getInnerText(html) {
                return html.replace(/<[^>]+>/g, '').replace(/\\\\s+/g, ' ').trim();
            }
            function extractBetween(str, start, end) {
                const s = str.indexOf(start);
                if (s === -1) return '';
                const e = str.indexOf(end, s + start.length);
                if (e === -1) return '';
                return str.substring(s + start.length, e);
            }
            function stripHtml(html)             { return html.replace(/<[^>]+>/g, ''); }
            function normalizeWhitespace(str)    { return str.replace(/\\\\s+/g, ' ').trim(); }
            function urlEncode(str)              { return encodeURIComponent(str); }
            function urlDecode(str)              { try { return decodeURIComponent(str); } catch(e) { return str; } }
            function htmlEntityDecode(str) {
                const entities = { quot: '"', apos: "'", amp: '&', lt: '<', gt: '>' };
                return str.replace(/&([a-zA-Z]+);/g, function(_, e) { return entities[e] || _; });
            }
            function transformResponse(response, fn) {
                try { return fn(response); } catch(e) { return response; }
            }
            """)
    }
    
    // MARK: - Full environment bootstrap
    
    func setupJavaScriptEnvironment() {
        setupWeirdCode()
        setupConsoleLogging()
        setupNativeFetch()
        setupNetworkFetch()
        setupNetworkFetchSimple()
        setupFetchV2()
        setupBase64Functions()
        setupUtilities()
    }
}
