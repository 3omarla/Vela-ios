import Foundation

/// Search, autocomplete and directions from Google's public web endpoints, keyless
/// (core GoogleMapsDataSource.kt).
enum GoogleMaps {
    static let nearbySpan = 2_500.0

    static func search(_ query: String, viewport: LatLng, spanMeters: Double?, user: LatLng?) async throws -> SearchResult {
        func page(_ at: LatLng, span: Double?) async throws -> SearchResult {
            let pb = SearchPb.build(query: query, viewport: at, spanMeters: span)
            let url = GoogleTransport.localized("\(Calibration.searchEndpoint)&q=\(query.urlEncoded)&pb=\(pb.urlEncoded)")
            let raw = try await GoogleTransport.shared.get(url)
            guard let root = PJ.parse(raw) else { throw CalibrationNeeded(detail: "search: not JSON") }
            return try SearchParser.parse(query: query, root: root, near: user ?? at)
        }
        // A second request over a tight window round the user leads the list when they are inside
        // a wider search window: Google's keyless ranking is prominence-heavy over the whole view.
        let wantNearby: Bool = {
            guard let user else { return false }
            guard let span = spanMeters else { return true }
            return user.distance(to: viewport) <= span / 2 && span > nearbySpan * 1.5
        }()
        async let main = page(viewport, span: spanMeters)
        async let near: SearchResult? = wantNearby ? (try? await page(user!, span: nearbySpan)) : nil
        var result = try await main
        if let n = await near, !result.focusedSingle {
            var seen = Set(result.places.map { $0.featureId ?? $0.id })
            let lead = n.places.prefix(3).filter { seen.insert($0.featureId ?? $0.id).inserted }
            result.places = lead + result.places
        }
        return result
    }

    static func suggest(_ query: String, near: LatLng, spanMeters: Double?) async throws -> SuggestResult {
        let span = RequestShape.span(min(max(spanMeters ?? 20_000, 2_000), 500_000))
        let (w, h) = BrowserViewport.size
        let pb = Calibration.suggestPb.replacingOccurrences(of: "{SPAN}", with: span)
            .replacingOccurrences(of: "{LNG}", with: String(near.lng)).replacingOccurrences(of: "{LAT}", with: String(near.lat))
            .replacingOccurrences(of: "{W}", with: String(w)).replacingOccurrences(of: "{H}", with: String(h))
        let url = GoogleTransport.localized("\(Calibration.suggestEndpoint)&pb=\(pb.urlEncoded)&q=\(query.urlEncoded)&tch=1&ech=\(RequestShape.nextEch())")
        return SuggestParser.parse(try await GoogleTransport.shared.get(url))
    }

    /// One place looked up again by name and address, for the full card a suggestion lacks.
    static func details(_ place: Place) async -> Place {
        let q = [place.name, place.address].compactMap { $0 }.joined(separator: " ")
        guard let r = try? await search(q, viewport: place.location, spanMeters: 3_000, user: nil) else { return place }
        let match = r.places.min { $0.location.distance(to: place.location) < $1.location.distance(to: place.location) }
        guard let m = match, m.location.distance(to: place.location) < 150 else { return place }
        var out = m
        out.distanceMeters = place.distanceMeters
        return out
    }

    static func directions(from o: LatLng, to d: LatLng, mode: TravelMode, waypoints: [LatLng] = [], prefs: RoutePrefs) async throws -> [Route] {
        let pb = DirectionsPb.build(origin: o, destination: d, mode: mode, waypoints: waypoints,
                                    avoidTolls: prefs.avoidTolls, avoidHighways: prefs.avoidHighways, avoidFerries: prefs.avoidFerries)
        let url = GoogleTransport.localized("\(Calibration.directionsEndpoint)&pb=\(pb.urlEncoded)")
        let raw = try await GoogleTransport.shared.get(url)
        guard let root = PJ.parse(raw) else { throw CalibrationNeeded(detail: "directions: not JSON") }
        return try DirectionsParser.parse(root, mode: mode)
    }
}
