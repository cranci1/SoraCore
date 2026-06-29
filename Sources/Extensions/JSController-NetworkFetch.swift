//
//  JSController-NetworkFetch.swift
//  Sora
//
//  Created by paul on 17/08/2025.
//

import WebKit
import JavaScriptCore

struct NetworkFetchOptions {
    let timeoutSeconds: Int
    let headers: [String: String]
    let cutoff: String?
    let returnHTML: Bool
    let returnCookies: Bool
    let clickSelectors: [String]
    let waitForSelectors: [String]
    let maxWaitTime: Int
    let htmlContent: String?
    
    init(
        timeoutSeconds: Int = 10,
        headers: [String: String] = [:],
        cutoff: String? = nil,
        returnHTML: Bool = false,
        returnCookies: Bool = true,
        clickSelectors: [String] = [],
        waitForSelectors: [String] = [],
        maxWaitTime: Int = 5,
        htmlContent: String? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.cutoff = cutoff
        self.returnHTML = returnHTML
        self.returnCookies = returnCookies
        self.clickSelectors = clickSelectors
        self.waitForSelectors = waitForSelectors
        self.maxWaitTime = maxWaitTime
        self.htmlContent = htmlContent
    }
    
    init(from dict: [AnyHashable: Any]) {
        self.init(
            timeoutSeconds: dict["timeoutSeconds"] as? Int ?? 10,
            headers: dict["headers"] as? [String: String] ?? [:],
            cutoff: dict["cutoff"] as? String,
            returnHTML: dict["returnHTML"] as? Bool ?? false,
            returnCookies: dict["returnCookies"]  as? Bool ?? true,
            clickSelectors: dict["clickSelectors"] as? [String] ?? [],
            waitForSelectors: dict["waitForSelectors"] as? [String] ?? [],
            maxWaitTime: dict["maxWaitTime"] as? Int ?? 5,
            htmlContent: dict["htmlContent"] as? String
        )
    }
}

// MARK: - JSContext extensions

extension JSContext {
    // MARK: networkFetch
    func setupNetworkFetch() {
        let native: @convention(block) (String, JSValue?, JSValue, JSValue) -> Void = {
            urlString, optionsValue, resolve, reject in
            DispatchQueue.main.async {
                let options = optionsValue?.toDictionary().map { NetworkFetchOptions(from: $0) }
                ?? NetworkFetchOptions()
                NetworkFetchManager.shared.performNetworkFetch(
                    urlString: urlString,
                    options: options,
                    resolve: resolve,
                    reject: reject
                )
            }
        }
        setObject(native, forKeyedSubscript: "networkFetchNative" as NSString)
        
        evaluateScript("""
            function networkFetch(url, options = {}) {
                if (typeof options === 'number') {
                    options = { timeoutSeconds: options, headers: arguments[2] || {}, cutoff: arguments[3] || null };
                }
                const o = {
                    timeoutSeconds:   options.timeoutSeconds   || 10,
                    headers:          options.headers          || {},
                    cutoff:           options.cutoff           || null,
                    returnHTML:       options.returnHTML       || false,
                    returnCookies:    options.returnCookies    !== undefined ? options.returnCookies : true,
                    clickSelectors:   options.clickSelectors   || [],
                    waitForSelectors: options.waitForSelectors || [],
                    maxWaitTime:      options.maxWaitTime      || 5,
                    htmlContent:      options.htmlContent      || null
                };
                return new Promise(function(resolve, reject) {
                    networkFetchNative(url, o, function(r) {
                        resolve({
                            url:             r.originalUrl,
                            requests:        r.requests,
                            html:            r.html             || null,
                            cookies:         r.cookies          || null,
                            success:         r.success,
                            error:           r.error            || null,
                            totalRequests:   r.requests.length,
                            cutoffTriggered: r.cutoffTriggered  || false,
                            cutoffUrl:       r.cutoffUrl        || null,
                            htmlCaptured:    r.htmlCaptured     || false,
                            cookiesCaptured: r.cookiesCaptured  || false,
                            elementsClicked: r.elementsClicked  || [],
                            waitResults:     r.waitResults      || {}
                        });
                    }, reject);
                });
            }
            
            function networkFetchWithHTML(url, timeoutSeconds = 10) {
                return networkFetch(url, { timeoutSeconds, returnHTML: true, returnCookies: true });
            }
            function networkFetchWithCutoff(url, cutoff, timeoutSeconds = 10) {
                return networkFetch(url, { timeoutSeconds, cutoff, returnCookies: true });
            }
            function networkFetchWithClicks(url, clickSelectors, options = {}) {
                return networkFetch(url, Object.assign({
                    clickSelectors: Array.isArray(clickSelectors) ? clickSelectors : [clickSelectors]
                }, options));
            }
            function networkFetchWithWaitAndClick(url, waitForSelectors, clickSelectors, options = {}) {
                return networkFetch(url, Object.assign({
                    waitForSelectors: Array.isArray(waitForSelectors) ? waitForSelectors : [waitForSelectors],
                    clickSelectors:   Array.isArray(clickSelectors)   ? clickSelectors   : [clickSelectors]
                }, options));
            }
            function networkFetchFromHTML(htmlContent, options = {}) {
                return networkFetch('', Object.assign({ htmlContent }, options));
            }
            """)
    }
    
    // MARK: networkFetchSimple
    
    func setupNetworkFetchSimple() {
        let native: @convention(block) (String, JSValue?, JSValue, JSValue) -> Void = {
            urlString, optionsValue, resolve, reject in
            DispatchQueue.main.async {
                let dict      = optionsValue?.toDictionary() ?? [:]
                let timeout   = dict["timeoutSeconds"] as? Int    ?? 5
                let html      = dict["htmlContent"]    as? String
                let headers   = dict["headers"]        as? [String: String] ?? [:]
                NetworkFetchSimpleManager.shared.performNetworkFetch(
                    urlString: urlString,
                    timeoutSeconds: timeout,
                    htmlContent: html,
                    headers: headers,
                    resolve: resolve,
                    reject: reject
                )
            }
        }
        setObject(native, forKeyedSubscript: "networkFetchSimpleNative" as NSString)
        
        evaluateScript("""
            function networkFetchSimple(url, options = {}) {
                if (typeof options === 'number') options = { timeoutSeconds: options };
                const o = {
                    timeoutSeconds: options.timeoutSeconds || 5,
                    htmlContent:    options.htmlContent    || null,
                    headers:        options.headers        || {}
                };
                return new Promise(function(resolve, reject) {
                    networkFetchSimpleNative(url, o, function(r) {
                        resolve({ url: r.originalUrl, requests: r.requests,
                                  success: r.success, error: r.error || null,
                                  totalRequests: r.requests.length });
                    }, reject);
                });
            }
            function networkFetchSimpleFromHTML(htmlContent, options = {}) {
                return networkFetchSimple('', Object.assign({ htmlContent }, options));
            }
            """)
    }
}

// MARK: - Shared JS injection code

private func makeNetworkInterceptionScript(includeClickSupport: Bool) -> WKUserScript {
    let clickSupportJS: String
    if includeClickSupport {
        clickSupportJS = """
            window.waitForElementAndClick = function(waitSelectors, clickSelectors, maxWaitTime) {
                return new Promise(function(resolve) {
                    const results = { waitResults: {}, clickResults: [] };
                    waitSelectors.forEach(function(s) { results.waitResults[s] = false; });
                    const start = Date.now();
            
                    const tick = function() {
                        waitSelectors.forEach(function(s) {
                            if (!results.waitResults[s]) {
                                const el = document.querySelector(s);
                                if (el && el.offsetParent !== null) results.waitResults[s] = true;
                            }
                        });
            
                        const allFound  = waitSelectors.every(function(s) { return results.waitResults[s]; });
                        const elapsed   = (Date.now() - start) / 1000;
            
                        if (allFound || elapsed >= maxWaitTime) {
                            clickSelectors.forEach(function(sel) {
                                try {
                                    let clicked = false;
                                    document.querySelectorAll(sel).forEach(function(el) {
                                        if (el && el.offsetParent !== null) {
                                            try { el.click(); clicked = true; }
                                            catch(e1) {
                                                try {
                                                    el.dispatchEvent(new MouseEvent('click',
                                                        { view: window, bubbles: true, cancelable: true }));
                                                    clicked = true;
                                                } catch(e2) {}
                                            }
                                        }
                                    });
                                    results.clickResults.push({ selector: sel, success: clicked });
                                } catch(e) {
                                    results.clickResults.push({ selector: sel, success: false, error: e.message });
                                }
                            });
                            window.webkit.messageHandlers.networkLogger.postMessage(
                                { type: 'click-results', results: results });
                            resolve(results);
                        } else {
                            setTimeout(tick, 100);
                        }
                    };
                    tick();
                });
            };
            """
    } else {
        clickSupportJS = ""
    }
    
    let source = """
        (function() {
            // --- Anti-detection ---
            Object.defineProperty(navigator, 'webdriver',    { get: () => undefined });
            Object.defineProperty(navigator, 'plugins',      { get: () => [1,2,3,4,5] });
            Object.defineProperty(navigator, 'languages',    { get: () => ['en-US','en'] });
            Object.defineProperty(navigator, 'permissions',  { get: () => undefined });
            try { delete window.navigator.__proto__.webdriver; } catch(e) {}
            window.chrome = { runtime: {} };
        
            const postURL = function(type, url) {
                window.webkit.messageHandlers.networkLogger.postMessage({ type: type, url: url });
            };
        
            // --- Patch fetch ---
            const _fetch = window.fetch;
            window.fetch = function() {
                try { postURL('fetch', new URL(arguments[0], location.href).href); }
                catch(e) { postURL('fetch', String(arguments[0])); }
                return _fetch.apply(this, arguments);
            };
        
            // --- Patch XHR ---
            const _xhrOpen = XMLHttpRequest.prototype.open;
            const _xhrSend = XMLHttpRequest.prototype.send;
        
            XMLHttpRequest.prototype.open = function() {
                try { this._url = new URL(arguments[1], location.href).href; }
                catch(e) { this._url = arguments[1]; }
                postURL('xhr-open', this._url);
        
                const _onReady = this.onreadystatechange;
                this.onreadystatechange = function() {
                    if (this.readyState === 4) {
                        if (this.responseURL) postURL('xhr-response', this.responseURL);
                        try {
                            const m = this.responseText.match(/(https?:\\/\\/[^\\s"'<>]+\\.(?:m3u8|ts|mp4|webm|mkv))/gi);
                            if (m) m.forEach(function(u) { postURL('response-content', u); });
                        } catch(e) {}
                    }
                    if (_onReady) _onReady.apply(this, arguments);
                };
                return _xhrOpen.apply(this, arguments);
            };
        
            XMLHttpRequest.prototype.send = function() {
                if (this._url) postURL('xhr-send', this._url);
                return _xhrSend.apply(this, arguments);
            };
        
            // --- Patch WebSocket ---
            const _ws = window.WebSocket;
            window.WebSocket = function(url, protocols) {
                postURL('websocket', url);
                return new _ws(url, protocols);
            };
        
            // --- Hook src setters on media/script elements ---
            ['HTMLVideoElement','HTMLSourceElement','HTMLScriptElement','HTMLImageElement'].forEach(function(cn) {
                const obj = window[cn];
                if (!obj || !obj.prototype) return;
                const desc = Object.getOwnPropertyDescriptor(obj.prototype, 'src');
                if (!desc || !desc.set) return;
                Object.defineProperty(obj.prototype, 'src', {
                    set: function(v) {
                        if (typeof v === 'string' && (v.includes('http') || v.includes('.m3u8') || v.includes('.ts')))
                            postURL('property-set', v);
                        return desc.set.call(this, v);
                    },
                    get: desc.get,
                    configurable: true
                });
            });
        
            // --- JWPlayer hook (retried until available) ---
            var _jwAttempts = 0;
            var _hookJW = function() {
                _jwAttempts++;
                if (window.jwplayer) {
                    const _origJW = window.jwplayer;
                    window.jwplayer = function(id) {
                        const p = _origJW.apply(this, arguments);
                        if (p && p.setup) {
                            const _setup = p.setup;
                            p.setup = function(cfg) {
                                (function scan(o) {
                                    if (!o) return;
                                    if (typeof o === 'string' && (o.includes('http') || o.includes('.m3u8')))
                                        postURL('jwplayer-config', o);
                                    else if (typeof o === 'object')
                                        Object.values(o).forEach(scan);
                                })(cfg);
                                return _setup.call(this, cfg);
                            };
                        }
                        return p;
                    };
                    Object.assign(window.jwplayer, _origJW);
                }
                if (_jwAttempts < 20) setTimeout(_hookJW, 200);
            };
            _hookJW();
        
            // --- Nuclear scan (media URLs in globals + inline scripts) ---
            var _scan = function() {
                Object.keys(window).forEach(function(k) {
                    try {
                        var v = window[k];
                        if (typeof v === 'string' && (v.includes('.m3u8') || v.includes('.ts') || v.includes('http')))
                            postURL('global-variable', v);
                    } catch(e) {}
                });
                document.querySelectorAll('script').forEach(function(s) {
                    if (!s.textContent) return;
                    var m = s.textContent.match(/(https?:\\/\\/[^\\s"'<>]+\\.(?:m3u8|ts|mp4))/gi);
                    if (m) m.forEach(function(u) { postURL('script-content', u); });
                });
            };
            [500, 1500, 3000].forEach(function(t) { setTimeout(_scan, t); });
        
            // --- Cookie capture ---
            window.captureCookies = function() {
                var c = {};
                document.cookie.split(';').forEach(function(pair) {
                    var p = pair.trim().split('=');
                    if (p.length === 2) c[p[0]] = decodeURIComponent(p[1]);
                });
                if (Object.keys(c).length)
                    window.webkit.messageHandlers.networkLogger.postMessage({ type: 'cookies', cookies: c });
                return c;
            };
            [1000, 3000, 5000].forEach(function(t) { setTimeout(window.captureCookies, t); });
        
            \(clickSupportJS)
        })();
        """
    
    return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
}

// MARK: - Common request builder

private func makeWebViewRequest(url: URL, headers: [String: String]) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(URLSession.randomUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
    request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
    request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue("upgrade-insecure-requests", forHTTPHeaderField: "Upgrade-Insecure-Requests")
    request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    if request.value(forHTTPHeaderField: "Referer") == nil {
        let referers = ["https://www.google.com/", "https://www.youtube.com/", "https://twitter.com/",    "https://www.reddit.com/", "https://www.facebook.com/"]
        request.setValue(referers.randomElement()!, forHTTPHeaderField: "Referer")
    }
    return request
}

// MARK: - NetworkFetchSimpleManager

final class NetworkFetchSimpleManager: NSObject {
    static let shared = NetworkFetchSimpleManager()
    private var monitors: [String: NetworkFetchSimpleMonitor] = [:]
    
    private override init() { super.init() }
    
    func performNetworkFetch(
        urlString: String,
        timeoutSeconds: Int,
        htmlContent: String?,
        headers: [String: String],
        resolve: JSValue,
        reject: JSValue
    ) {
        let id = UUID().uuidString
        let monitor = NetworkFetchSimpleMonitor()
        monitors[id] = monitor
        
        monitor.startMonitoring(
            urlString: urlString,
            timeoutSeconds: timeoutSeconds,
            htmlContent: htmlContent,
            headers: headers
        ) { [weak self] result in
            self?.monitors.removeValue(forKey: id)
            DispatchQueue.main.async {
                if !resolve.isUndefined { resolve.call(withArguments: [result]) }
            }
        }
    }
}

// MARK: - NetworkFetchSimpleMonitor

final class NetworkFetchSimpleMonitor: NSObject {
    private var webView: WKWebView?
    private var completion: (([String: Any]) -> Void)?
    private var timer: Timer?
    private var originalUrl = ""
    private var requests: [String] = []
    
    func startMonitoring(
        urlString: String,
        timeoutSeconds: Int,
        htmlContent: String?,
        headers: [String: String],
        completion: @escaping ([String: Any]) -> Void
    ) {
        self.originalUrl = urlString
        self.completion  = completion
        requests.removeAll()
        setupWebView()
        
        if let html = htmlContent, !html.isEmpty {
            addRequest("data:text/html;charset=utf-8,<html_content>")
            webView?.loadHTMLString(html, baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.simulateInteraction() }
        } else {
            guard let url = URL(string: urlString) else {
                completion(["originalUrl": urlString, "requests": [], "success": false, "error": "Invalid URL format"])
                return
            }
            webView?.load(makeWebViewRequest(url: url, headers: headers))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.simulateInteraction() }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { [weak self] _ in
            self?.finish()
        }
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(makeNetworkInterceptionScript(includeClickSupport: false))
        config.userContentController.add(self, name: "networkLogger")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        webView?.navigationDelegate = self
        webView?.customUserAgent = URLSession.randomUserAgent
    }
    
    private func simulateInteraction() {
        webView?.evaluateJavaScript(playInteractionScript(), completionHandler: nil)
    }
    
    private func finish() {
        timer?.invalidate()
        timer = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "networkLogger")
        
        let result: [String: Any] = [
            "originalUrl": webView?.url?.absoluteString ?? originalUrl,
            "requests": requests,
            "success": true,
        ]
        webView = nil
        completion?(result)
        completion = nil
    }
    
    private func addRequest(_ url: String) {
        DispatchQueue.main.async {
            if !self.requests.contains(url) { self.requests.append(url) }
        }
    }
}

extension NetworkFetchSimpleMonitor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url { addRequest(url.absoluteString) }
        decisionHandler(.allow)
    }
}

extension NetworkFetchSimpleMonitor: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "networkLogger",
              let body = message.body as? [String: Any],
              let url  = body["url"] as? String else { return }
        addRequest(url)
    }
}

// MARK: - NetworkFetchManager

final class NetworkFetchManager: NSObject {
    static let shared = NetworkFetchManager()
    private var monitors: [String: NetworkFetchMonitor] = [:]
    
    private override init() { super.init() }
    
    func performNetworkFetch(
        urlString: String,
        options: NetworkFetchOptions,
        resolve: JSValue,
        reject: JSValue
    ) {
        let id = UUID().uuidString
        let monitor = NetworkFetchMonitor()
        monitors[id] = monitor
        
        monitor.startMonitoring(urlString: urlString, options: options) { [weak self] result in
            self?.monitors.removeValue(forKey: id)
            DispatchQueue.main.async {
                if !resolve.isUndefined { resolve.call(withArguments: [result]) }
            }
        }
    }
}

// MARK: - NetworkFetchMonitor

final class NetworkFetchMonitor: NSObject {
    private var webView: WKWebView?
    private var completion: (([String: Any]) -> Void)?
    private var timer: Timer?
    private var options: NetworkFetchOptions?
    
    private var requests: [String] = []
    private var elementsClicked: [String] = []
    private var waitResults: [String: Bool] = [:]
    private var cookies: [String: String] = [:]
    private var capturedHTML: String?
    private var htmlCaptured = false
    private var cookiesCaptured = false
    private var cutoffTriggered = false
    private var cutoffUrl: String?
    
    func startMonitoring(
        urlString: String,
        options: NetworkFetchOptions,
        completion: @escaping ([String: Any]) -> Void
    ) {
        self.options = options
        self.completion = completion
        
        setupWebView()
        
        if let html = options.htmlContent, !html.isEmpty {
            addRequest("data:text/html;charset=utf-8,<html_content>")
            webView?.loadHTMLString(html, baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.performInteractions()
                if options.returnCookies { self.captureCookies { } }
            }
        } else {
            guard let url = URL(string: urlString) else {
                completion(makeResultDict(originalUrl: urlString, success: false, error: "Invalid URL format"))
                return
            }
            webView?.load(makeWebViewRequest(url: url, headers: options.headers))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.performInteractions()
                if options.returnCookies { self.captureCookies { } }
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(options.timeoutSeconds), repeats: false) { [weak self] _ in
            if options.returnHTML || options.returnCookies {
                self?.captureDataThenFinish()
            } else {
                self?.finish()
            }
        }
    }
    
    // MARK: Helpers
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(makeNetworkInterceptionScript(includeClickSupport: true))
        config.userContentController.add(self, name: "networkLogger")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        webView?.navigationDelegate = self
        webView?.customUserAgent = URLSession.randomUserAgent
    }
    
    private func performInteractions() {
        guard let webView, let opts = options else { return }
        
        if !opts.waitForSelectors.isEmpty || !opts.clickSelectors.isEmpty {
            let waitJS  = opts.waitForSelectors.map { "'\($0)'" }.joined(separator: ", ")
            let clickJS = opts.clickSelectors.map { "'\($0)'" }.joined(separator: ", ")
            webView.evaluateJavaScript(
                "window.waitForElementAndClick([\(waitJS)], [\(clickJS)], \(opts.maxWaitTime));",
                completionHandler: nil
            )
        } else {
            webView.evaluateJavaScript(playInteractionScript(), completionHandler: nil)
        }
    }
    
    private func captureDataThenFinish() {
        guard let webView, let opts = options else { finish(); return }
        
        var pending = (opts.returnHTML ? 1 : 0) + (opts.returnCookies ? 1 : 0)
        guard pending > 0 else { finish(); return }
        
        let done = {
            pending -= 1
            if pending == 0 { self.finish() }
        }
        
        if opts.returnHTML {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                DispatchQueue.main.async {
                    if let html = result as? String, error == nil {
                        self?.capturedHTML  = html
                        self?.htmlCaptured  = true
                    }
                    done()
                }
            }
        }
        if opts.returnCookies {
            captureCookies { done() }
        }
    }
    
    private func captureCookies(completion: @escaping () -> Void) {
        guard let webView else { completion(); return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] list in
            DispatchQueue.main.async {
                list.forEach { self?.cookies[$0.name] = $0.value }
                self?.cookiesCaptured = !(self?.cookies.isEmpty ?? true)
                completion()
            }
        }
    }
    
    private func finish() {
        timer?.invalidate()
        timer = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "networkLogger")
        
        let originalUrl = options?.htmlContent != nil
        ? "data:text/html;charset=utf-8,<html_content>"
        : (webView?.url?.absoluteString ?? "")
        
        let result = makeResultDict(originalUrl: originalUrl, success: true)
        webView = nil
        completion?(result)
        completion = nil
    }
    
    private func makeResultDict(originalUrl: String, success: Bool, error: String? = nil) -> [String: Any] {
        [
            "originalUrl": originalUrl,
            "requests": requests,
            "html": capturedHTML as Any,
            "cookies": cookies.isEmpty ? NSNull() : cookies,
            "success": success,
            "error": error as Any,
            "cutoffTriggered": cutoffTriggered,
            "cutoffUrl": cutoffUrl as Any,
            "htmlCaptured": htmlCaptured,
            "cookiesCaptured": cookiesCaptured,
            "elementsClicked": elementsClicked,
            "waitResults": waitResults,
        ]
    }
    
    private func addRequest(_ url: String) {
        DispatchQueue.main.async {
            guard !self.requests.contains(url) else { return }
            self.requests.append(url)
            
            if let cutoff = self.options?.cutoff, !cutoff.isEmpty,
               url.lowercased().contains(cutoff.lowercased()) {
                self.cutoffTriggered = true
                self.cutoffUrl = url
                self.finish()
            }
        }
    }
}

extension NetworkFetchMonitor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url { addRequest(url.absoluteString) }
        decisionHandler(.allow)
    }
}

extension NetworkFetchMonitor: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "networkLogger",
              let body = message.body as? [String: Any] else { return }
        
        if let url = body["url"] as? String {
            addRequest(url)
            return
        }
        
        guard let type = body["type"] as? String else { return }
        
        switch type {
        case "click-results":
            guard let results = body["results"] as? [String: Any] else { return }
            if let clickResults = results["clickResults"]  as? [[String: Any]] {
                DispatchQueue.main.async {
                    for r in clickResults {
                        if let sel = r["selector"] as? String, r["success"] as? Bool == true {
                            self.elementsClicked.append(sel)
                        }
                    }
                }
            }
            if let wr = results["waitResults"] as? [String: Bool] {
                DispatchQueue.main.async { self.waitResults = wr }
            }
            
        case "cookies":
            if let incoming = body["cookies"] as? [String: String] {
                DispatchQueue.main.async {
                    incoming.forEach { self.cookies[$0.key] = $0.value }
                    self.cookiesCaptured = !self.cookies.isEmpty
                }
            }
            
        default: break
        }
    }
}

// MARK: - Shared play-interaction JS snippet

private func playInteractionScript() -> String {
    """
    setTimeout(function() {
        Array.from(document.querySelectorAll('button, div, span, a')).filter(function(el) {
            var t = (el.textContent || el.innerText || '').toLowerCase();
            var c = (el.className || '').toLowerCase();
            var i = (el.id || '').toLowerCase();
            return t.includes('play') || c.includes('play') || i.includes('play') ||
                   (el.getAttribute('aria-label') || '').toLowerCase().includes('play');
        }).forEach(function(el, idx) {
            setTimeout(function() { try { el.click(); } catch(e) {} }, idx * 200);
        });
    
        window.scrollTo(0, document.body.scrollHeight / 2);
        setTimeout(function() { window.scrollTo(0, 0); }, 500);
    
        document.querySelectorAll('video').forEach(function(v) {
            if (v.play) v.play().catch(function() {});
        });
    
        if (window.jwplayer) {
            try { (window.jwplayer().getInstances?.() || []).forEach(function(p) { if (p.play) p.play(); }); }
            catch(e) {}
        }
        if (window.videojs) {
            try { (window.videojs.getAllPlayers?.() || []).forEach(function(p) { if (p.play) p.play(); }); }
            catch(e) {}
        }
    }, 1000);
    """
}
