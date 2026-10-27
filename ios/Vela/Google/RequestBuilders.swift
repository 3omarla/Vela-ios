import Foundation

/// The browser window the requests describe (core BrowserViewport.kt). Each install picks one
/// common maximized desktop Chrome size once and keeps it.
enum BrowserViewport {
    static let choices: [(Int, Int)] = [
        (1920, 945), (1920, 945), (1920, 945), (1536, 730), (1536, 730), (1366, 641), (1366, 641),
        (1440, 781), (1600, 773), (1280, 632), (1680, 925), (2560, 1305),
    ]

    static let size: (w: Int, h: Int) = {
        let key = "browser_viewport_index"
        let d = UserDefaults.standard
        if d.object(forKey: key) == nil { d.set(Int.random(in: 0..<choices.count), forKey: key) }
        let c = choices[((d.integer(forKey: key) % choices.count) + choices.count) % choices.count]
        return (c.0, c.1)
    }()

    private static let capturedSize = "!3m2!1i1024!2i768"
    private static let capturedRects = "m28!1m6!1m2!1i0!2i0!2m2!1i530!2i768!1m6!1m2!1i974!2i0!2m2!1i1024!2i768" +
        "!1m6!1m2!1i0!2i0!2m2!1i1024!2i20!1m6!1m2!1i0!2i748!2m2!1i1024!2i768"

    static func apply(_ pb: String) -> String {
        let (w, h) = size
        if w == 1024 && h == 768 { return pb }
        let rects = "m28!1m6!1m2!1i0!2i0!2m2!1i530!2i\(h)!1m6!1m2!1i\(w - 50)!2i0!2m2!1i\(w)!2i\(h)" +
            "!1m6!1m2!1i0!2i0!2m2!1i\(w)!2i20!1m6!1m2!1i0!2i\(h - 20)!2m2!1i\(w)!2i\(h)"
        return pb.replacingOccurrences(of: capturedSize, with: "!3m2!1i\(w)!2i\(h)")
            .replacingOccurrences(of: capturedRects, with: rects)
    }
}

/// Per-session values Google's own pages vary (core RequestShape.kt).
enum RequestShape {
    private static var ech = 0
    private static let lock = NSLock()

    /// A map span as a browser writes one: a long decimal never the same twice.
    static func span(_ meters: Double) -> String {
        String(meters * (1 + (Double.random(in: 0..<1) - 0.5) * 0.004))
    }

    static func nextEch() -> Int {
        lock.lock(); defer { lock.unlock() }
        ech += 1
        return ech
    }

    /// The directions request's map viewport centered on the trip, spanning it with a margin.
    static func fitDirections(_ pb: String, points: [LatLng]) -> String {
        guard !points.isEmpty,
              let m = pb.firstMatch(#"(!3m12!1m3!1d)[0-9.]+(!2d)-?[0-9.]+(!3d)-?[0-9.]+"#),
              let range = pb.range(of: m[0]) else { return pb }
        let s = points.map(\.lat).min()!, n = points.map(\.lat).max()!
        let w = points.map(\.lng).min()!, e = points.map(\.lng).max()!
        let lat = (s + n) / 2, lng = (w + e) / 2
        let spanM = max((n - s) * 111_320, (e - w) * 111_320 * cos(lat * .pi / 180))
        let d = span(max(spanM * 1.35, 1_500))
        return pb.replacingCharacters(in: range, with: "\(m[1])\(d)\(m[2])\(lng)\(m[3])\(lat)")
    }
}

/// The `pb` parameter for `/search?tbm=map` (core SearchPb.kt).
enum SearchPb {
    static let minSpan = 1_000.0

    static func build(query: String, viewport: LatLng, spanMeters: Double? = nil, offset: Int = 0) -> String {
        var pb = Calibration.searchPb
            .replacingOccurrences(of: "{QUERY}", with: query.replacingOccurrences(of: "!", with: " ").trimmingCharacters(in: .whitespaces))
            .replacingOccurrences(of: "{LNG}", with: String(viewport.lng))
            .replacingOccurrences(of: "{LAT}", with: String(viewport.lat))
        if let m = pb.firstMatch(#"!1d([0-9.]+)"#), let r = pb.range(of: m[0]) {
            let base = spanMeters.map { min(max($0, minSpan), 500_000) } ?? Double(m[1]) ?? 25_000
            pb.replaceSubrange(r, with: "!1d\(RequestShape.span(base))")
        }
        if offset > 0, let m = pb.firstMatch(#"!7i\d+"#), let r = pb.range(of: m[0]) {
            pb.replaceSubrange(r, with: "\(m[0])!8i\(offset)")
        }
        return BrowserViewport.apply(pb)
    }
}

/// The `pb` parameter for `/maps/preview/directions` (core DirectionsPb.kt).
enum DirectionsPb {
    static func build(origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: [LatLng] = [],
                      avoidTolls: Bool, avoidHighways: Bool, avoidFerries: Bool) -> String {
        let drive = mode == .drive
        var pb = RequestShape.fitDirections(Calibration.directionsPb, points: [origin] + waypoints + [destination])
        pb = withAvoid(pb, tolls: avoidTolls && drive, highways: avoidHighways && drive, ferries: avoidFerries && drive)
        pb = withWaypoints(pb, waypoints)
        return BrowserViewport.apply(pb)
            .replacingOccurrences(of: "{OLAT}", with: String(origin.lat))
            .replacingOccurrences(of: "{OLNG}", with: String(origin.lng))
            .replacingOccurrences(of: "{DLAT}", with: String(destination.lat))
            .replacingOccurrences(of: "{DLNG}", with: String(destination.lng))
            .replacingOccurrences(of: "{MODE}", with: String(mode.googleCode))
    }

    /// A stop is one more top-level waypoint group before the destination's.
    static func withWaypoints(_ pb: String, _ waypoints: [LatLng]) -> String {
        guard !waypoints.isEmpty, let r = pb.range(of: "!1m4!3m2!3d{DLAT}!4d{DLNG}!6e2") else { return pb }
        let groups = waypoints.map { "!1m4!3m2!3d\($0.lat)!4d\($0.lng)!6e2" }.joined()
        var out = pb
        out.insert(contentsOf: groups, at: r.lowerBound)
        return out
    }

    private struct Child { let field: Int; let type: Character; let start: Int; let end: Int }

    /// Avoid flags in the `!6m` feature block: inside its `!2m` submessage `!1b1` avoids highways
    /// and `!2b1` tolls; `!7b1` avoids ferries as a direct child of the outer block.
    static func withAvoid(_ pb: String, tolls: Bool, highways: Bool, ferries: Bool) -> String {
        let ns = pb as NSString
        guard let re = try? NSRegularExpression(pattern: #"!6m(\d+)(!1m5!18b1!30b1!31m1!1b1!34e1!2m)(\d+)"#),
              let m = re.firstMatch(in: pb, range: NSRange(location: 0, length: ns.length)) else { return pb }
        let outerCount = Int(ns.substring(with: m.range(at: 1)))!
        let innerCount = Int(ns.substring(with: m.range(at: 3)))!
        let head = ns.substring(with: m.range(at: 2))
        var flags = ""
        if highways { flags += "!1b1" }
        if tolls { flags += "!2b1" }
        let added = flags.filter { $0 == "!" }.count
        let bodyStart = m.range.location + 3 + m.range(at: 1).length
        let children = directChildren(ns, from: bodyStart, count: outerCount)
        var ferryEdit: (NSRange, String)?
        var ferryDelta = 0
        if let f = children?.first(where: { $0.field == 7 && $0.type == "b" }) {
            let want = ferries ? "!7b1" : "!7b0"
            let r = NSRange(location: f.start, length: f.end - f.start)
            if ns.substring(with: r) != want { ferryEdit = (r, want) }
        } else if ferries, let children {
            let at = children.first(where: { $0.field > 7 })?.start ?? children.last?.end ?? bodyStart
            ferryEdit = (NSRange(location: at, length: 0), "!7b1")
            ferryDelta = 1
        }
        if added == 0 && ferryEdit == nil { return pb }
        let out = NSMutableString(string: pb)
        if let (r, t) = ferryEdit { out.replaceCharacters(in: r, with: t) }
        out.replaceCharacters(in: m.range, with: "!6m\(outerCount + added + ferryDelta)\(head)\(innerCount + added)\(flags)")
        return out as String
    }

    private static func directChildren(_ pb: NSString, from: Int, count: Int) -> [Child]? {
        guard let re = try? NSRegularExpression(pattern: #"!(\d+)([a-zA-Z])([^!]*)"#) else { return nil }
        let tokens = Array(re.matches(in: pb as String, range: NSRange(location: from, length: pb.length - from)).prefix(count))
        guard tokens.count == count else { return nil }
        var out: [Child] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if i > 0 && t.range.location != tokens[i - 1].range.location + tokens[i - 1].range.length { return nil }
            let type = Character(pb.substring(with: t.range(at: 2)))
            let span = type == "m" ? (Int(pb.substring(with: t.range(at: 3))) ?? -1) : 0
            if span < 0 { return nil }
            let last = i + span
            if last >= tokens.count { return nil }
            out.append(Child(field: Int(pb.substring(with: t.range(at: 1)))!, type: type, start: t.range.location,
                             end: tokens[last].range.location + tokens[last].range.length))
            i = last + 1
        }
        return out
    }
}
