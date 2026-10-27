import Foundation

/// Keyless, accountless access to Google's public web endpoints, as one logged-out desktop
/// Chrome (core BrowserHeaders.kt, GoogleSession.kt, CoreModule's consent cookies).
actor GoogleTransport {
    static let shared = GoogleTransport()

    private let session: URLSession
    private var warmed = false

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
        // Consent cookies, so EU sessions are not bounced to the consent wall.
        for (name, value) in [("SOCS", "CAESHAgBEhIaAB"), ("CONSENT", "YES+")] {
            if let c = HTTPCookie(properties: [.domain: ".google.com", .path: "/", .name: name, .value: value,
                                               .expires: Date().addingTimeInterval(86_400 * 365)]) {
                HTTPCookieStorage.shared.setCookie(c)
            }
        }
    }

    static let mapsReferer = "https://www.google.com/maps/"

    /// Accept-Language from the phone's preferred languages: each tag, then its bare language,
    /// q from 0.9 down by 0.1.
    static var acceptLanguage: String {
        var tags: [String] = []
        for t in Locale.preferredLanguages.prefix(3) {
            if !tags.contains(t) { tags.append(t) }
            let bare = String(t.prefix { $0 != "-" })
            if !tags.contains(bare) { tags.append(bare) }
        }
        if tags.isEmpty { tags = ["en-US", "en"] }
        return tags.enumerated().map { i, t in i == 0 ? t : "\(t);q=\(String(format: "%.1f", max(0.1, 1 - Double(i) * 0.1)))" }
            .joined(separator: ",")
    }

    private func baseHeaders(_ req: inout URLRequest) {
        req.setValue(Calibration.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        req.setValue(Calibration.secChUa, forHTTPHeaderField: "Sec-CH-UA")
        req.setValue("?0", forHTTPHeaderField: "Sec-CH-UA-Mobile")
        req.setValue("\"Windows\"", forHTTPHeaderField: "Sec-CH-UA-Platform")
    }

    func ensureSession() async {
        if warmed { return }
        guard let url = URL(string: Calibration.sessionWarmUrl) else { return }
        var req = URLRequest(url: url)
        baseHeaders(&req)
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
                     forHTTPHeaderField: "Accept")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        _ = try? await session.data(for: req)
        warmed = true
    }

    /// A data call, as the maps page makes it.
    func get(_ urlString: String) async throws -> String {
        await ensureSession()
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        baseHeaders(&req)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue(Self.mapsReferer, forHTTPHeaderField: "Referer")
        req.setValue("10", forHTTPHeaderField: "Downlink")
        req.setValue("50", forHTTPHeaderField: "RTT")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 429 || http.statusCode == 403 { warmed = false }
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The `hl`/`gl` pair rewritten to the phone's language (when the status parser knows it)
    /// and region.
    static func localized(_ url: String) -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier.lowercased() ?? "us"
        var u = url
        if SearchParser.statusLangs.contains(lang) { u = u.replacingOccurrences(of: "hl=en", with: "hl=\(lang)") }
        return u.replacingOccurrences(of: "gl=us", with: "gl=\(region)")
    }
}

/// Requests to community services (OSRM, Nominatim, Photon), with Vela's contactable UA.
enum OpenHTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        return URLSession(configuration: cfg)
    }()

    static func getJSON(_ urlString: String, timeout: TimeInterval = 12) async throws -> Any {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(Calibration.velaUA, forHTTPHeaderField: "User-Agent")
        req.setValue(GoogleTransport.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data)
    }
}
