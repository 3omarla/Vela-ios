import Foundation

struct RoutePrefs: Codable, Equatable {
    var avoidTolls = false
    var avoidHighways = false
    var avoidFerries = false

    var osrmExclude: [String] {
        var e: [String] = []
        if avoidTolls { e.append("toll") }
        if avoidHighways { e.append("motorway") }
        if avoidFerries { e.append("ferry") }
        return e
    }
}

enum RouteIndex {
    /// Puts each maneuver at its meters along the polyline, walking forward so a road driven out
    /// and back resolves to the right pass.
    static func indexManeuvers(_ route: inout Route) {
        let line = route.polyline
        guard line.count >= 2 else { return }
        let cum = Geo.cumulative(line)
        var from = 0.0
        for i in route.maneuvers.indices {
            let m = route.maneuvers[i]
            if m.type == .depart { route.maneuvers[i].alongMeters = 0; continue }
            if m.type == .arrive || i == route.maneuvers.count - 1 { route.maneuvers[i].alongMeters = cum.last!; continue }
            let segs = Geo.segments(cum: cum, from: from, to: from + max(m.distanceMeters, 0) + 5_000)
            if let p = Geo.project(m.location, on: line, cum: cum, segments: 0...(line.count - 2)).flatMap({ whole in
                Geo.project(m.location, on: line, cum: cum, segments: segs).map { $0.offMeters < 30 ? $0 : whole }
            }) {
                route.maneuvers[i].alongMeters = max(from, p.alongMeters)
                from = route.maneuvers[i].alongMeters
            }
        }
    }
}

/// Which source answers a trip (SPEC 4.1, simplified):
/// - Drive: Google's line, live traffic and alternates. Each Google route is followed by the open
///   router through bearing-locked vias sampled along it, which gives exact OpenStreetMap turns on
///   Google's course; when that does not agree with Google's length, Google's own steps are used.
/// - Walk and bicycle: the open router.
/// - Google unreachable: the open router for every mode.
enum RouteService {
    static func routes(from o: LatLng, to d: LatLng, mode: TravelMode, prefs: RoutePrefs, urgent: Bool = false) async throws -> [Route] {
        guard mode == .drive else {
            return try await OSRM.route([o, d], mode: mode, options: .init(alternatives: !urgent))
        }
        if urgent {
            // A reroute mid-drive cannot wait for the full hybrid: Google's line is taken if it is
            // matched inside the grace, else the open router's direct answer goes out now and the
            // drive's traffic recheck brings Google's course back.
            async let open = try? OSRM.route([o, d], mode: .drive, options: .init(exclude: prefs.osrmExclude), timeout: 4).first
            let google = await withTimeout(seconds: urgentGrace) { () -> Route? in
                guard let g = try? await GoogleMaps.directions(from: o, to: d, mode: .drive, prefs: prefs).first else { return nil }
                return await hybrid(g, prefs: prefs, timeout: 2)
            }
            if let g = google ?? nil { return [g] }
            if let r = await open { return [r] }
            throw URLError(.cannotConnectToHost)
        }
        if let google = try? await GoogleMaps.directions(from: o, to: d, mode: .drive, prefs: prefs), !google.isEmpty {
            return await withTaskGroup(of: (Int, Route).self) { group in
                for (i, g) in google.prefix(3).enumerated() {
                    group.addTask { (i, await hybrid(g, prefs: prefs, timeout: 8)) }
                }
                var out = [(Int, Route)]()
                for await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
        return try await OSRM.route([o, d], mode: .drive, options: .init(alternatives: true, exclude: prefs.osrmExclude))
    }

    static let urgentGrace: TimeInterval = 3

    /// [op]'s result, or nil when it has not answered within [seconds].
    static func withTimeout<T: Sendable>(seconds: TimeInterval, _ op: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func hybrid(_ g: Route, prefs: RoutePrefs, timeout: TimeInterval) async -> Route {
        let line = g.polyline
        let cum = Geo.cumulative(line)
        let total = cum.last ?? 0
        guard total > 50 else { return indexed(g) }
        // One via every ~1.2 km, at most 40, each held to Google's direction of travel there.
        let n = max(0, min(40, Int(total / 1_200) - 1))
        var coords = [line.first!]
        var bearings = [""]
        var radiuses = ["unlimited"]
        if n > 0 {
            for k in 1...n {
                let at = total * Double(k) / Double(n + 1)
                coords.append(Geo.point(along: line, cum: cum, meters: at))
                bearings.append("\(Int(Geo.bearing(along: line, cum: cum, meters: at).rounded()) % 360),30")
                radiuses.append("20")
            }
        }
        coords.append(line.last!)
        bearings.append("")
        radiuses.append("unlimited")
        var opts = OSRM.Options(waypoints: [0, coords.count - 1], bearings: bearings, radiuses: radiuses, exclude: prefs.osrmExclude)
        var open = try? await OSRM.route(coords, mode: .drive, options: opts, timeout: timeout).first
        if open == nil {
            opts.waypoints = nil
            open = try? await OSRM.route(coords, mode: .drive, options: opts, timeout: timeout).first
        }
        guard var o = open, abs(o.distanceMeters - g.distanceMeters) <= g.distanceMeters * 0.07 + 200 else {
            vlog.info("hybrid: kept Google steps (open \(open.map { Int($0.distanceMeters) } ?? -1) m vs google \(Int(g.distanceMeters)) m)")
            return indexed(g)
        }
        vlog.info("hybrid: open router matched \(Int(o.distanceMeters)) m vs google \(Int(g.distanceMeters)) m, \(o.maneuvers.count) steps")
        // Google's times and congestion on the open router's matched line.
        let scale = o.distanceMeters / max(g.distanceMeters, 1)
        o.source = .googleHybrid
        o.durationSeconds = g.durationSeconds
        o.durationInTrafficSeconds = g.durationInTrafficSeconds
        o.typicalLowSeconds = g.typicalLowSeconds
        o.typicalHighSeconds = g.typicalHighSeconds
        o.summary = g.summary ?? o.summary
        o.distanceMeters = g.distanceMeters
        o.trafficSpans = g.trafficSpans.map { TrafficSpan(level: $0.level, startMeters: $0.startMeters * scale, lengthMeters: $0.lengthMeters * scale) }
        return o
    }

    private static func indexed(_ r: Route) -> Route {
        var r = r
        if r.maneuvers.isEmpty {
            r.maneuvers = [Maneuver(type: .depart, instruction: "Head out", location: r.polyline.first!, distanceMeters: r.distanceMeters),
                           Maneuver(type: .arrive, instruction: "You have arrived at your destination", location: r.polyline.last!,
                                    distanceMeters: 0, alongMeters: Geo.length(r.polyline))]
        }
        return r
    }
}
