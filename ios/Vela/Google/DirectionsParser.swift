import Foundation

/// Parses the `/maps/preview/directions` response (core DirectionsParser.kt).
enum DirectionsParser {
    static func parse(_ root: PJ, mode: TravelMode, paths P: [String: [Int]] = Calibration.directionsPaths) throws -> [Route] {
        guard let routes = root.at(P["routes"]).arr else { throw CalibrationNeeded(detail: "directions routes") }
        let geoms = root.at(P["geometries"]).arr
        let parsed = routes.enumerated().compactMap { i, r in
            parseRoute(r, geometry: decodeGeometry(geoms.flatMap { i < $0.count ? $0[i] : nil }), mode: mode, P: P)
        }
        if parsed.isEmpty { throw CalibrationNeeded(detail: "directions: 0 routes parsed") }
        return parsed
    }

    private static func parseRoute(_ route: PJ, geometry: [LatLng]?, mode: TravelMode, P: [String: [Int]]) -> Route? {
        let summary = route.at(P["summary"])
        guard let distance = summary.at(P["distance"]).dbl, let typical = summary.at(P["typical"]).dbl else { return nil }
        let start = coord(summary.at(P["start"])), end = coord(summary.at(P["end"]))
        let line = (geometry?.count ?? 0) >= 2 ? geometry! : [start, end].compactMap { $0 }
        guard line.count >= 2 else { return nil }
        let spans = (route.at(P["spans"]).arr ?? []).compactMap { s -> TrafficSpan? in
            guard let level = s.at(0).int, let st = s.at(1).dbl, let len = s.at(2).dbl, len > 0, level >= 1 else { return nil }
            return TrafficSpan(level: level, startMeters: st, lengthMeters: len)
        }.sorted { $0.startMeters < $1.startMeters }
        return Route(
            source: .googleNamed, mode: mode, polyline: line,
            maneuvers: placeManeuvers(collectSteps(route), polyline: line),
            distanceMeters: distance, durationSeconds: typical,
            durationInTrafficSeconds: summary.at(P["traffic"]).dbl,
            summary: summary.at(P["summaryText"]).str, trafficSpans: spans,
            typicalLowSeconds: summary.at(P["typicalLow"]).dbl, typicalHighSeconds: summary.at(P["typicalHigh"]).dbl
        )
    }

    /// `[0]` latitude deltas, `[1]` longitude deltas, E7, first element absolute.
    private static func decodeGeometry(_ node: PJ?) -> [LatLng]? {
        guard let node, let lat = node.at(0).arr, let lng = node.at(1).arr, lat.count == lng.count, lat.count >= 2 else { return nil }
        var la: Int64 = 0, ln: Int64 = 0
        return lat.indices.map { i in
            la += lat[i].int64 ?? 0
            ln += lng[i].int64 ?? 0
            return LatLng(Double(la) / 1e7, Double(ln) / 1e7)
        }
    }

    private static func coord(_ n: PJ) -> LatLng? {
        guard let lat = n.at(2).dbl, let lng = n.at(3).dbl else { return nil }
        return LatLng(lat, lng)
    }

    private static func collectSteps(_ route: PJ) -> [Maneuver] {
        route.strings().filter { $0.contains("<step ") }.map(parseStep)
    }

    static func parseStep(_ s: String) -> Maneuver {
        let token = s.firstMatch("maneuver='([^']+)'")?[1]
        let side = s.firstMatch(#"<turn\b[^>]*\bside='([^']+)'"#, options: .caseInsensitive)?[1]
        let severity = s.firstMatch(#"<turn\b[^>]*\btype='([^']+)'"#, options: .caseInsensitive)?[1]
        let meters = s.firstMatch("meters='([0-9]+)'").flatMap { Double($0[1]) } ?? 0
        let road = s.firstMatch("<road>([^<]+)</road>")?[1]
        let text = s.replacing("<[^>]+>", with: " ").replacing(#"\s+"#, with: " ").trimmingCharacters(in: .whitespaces)
        var laneHint: String?
        var instruction = text
        if let m = text.firstMatch(#"^(Use (?:the .+? lanes?|any lane)) to "#, options: .caseInsensitive) {
            laneHint = m[1]
            instruction = String(text.dropFirst(m[0].count))
        }
        instruction = instruction.prefix(1).uppercased() + instruction.dropFirst()
        return Maneuver(type: mapType(token, side: side, severity: severity), instruction: instruction.isEmpty ? "Continue" : instruction,
                        location: LatLng(0, 0), distanceMeters: meters, road: road.map(decodeEntities), laneHint: laneHint)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
    }

    static func mapType(_ token: String?, side: String?, severity: String?) -> ManeuverType {
        let left = side?.uppercased() == "LEFT", right = side?.uppercased() == "RIGHT"
        let slight = severity?.uppercased() == "SLIGHT", sharp = severity?.uppercased() == "SHARP"
        func lr(_ l: ManeuverType, _ r: ManeuverType, _ fb: ManeuverType) -> ManeuverType { left ? l : right ? r : fb }
        switch token?.uppercased() {
        case "DEPART": return .depart
        case "DESTINATION", "ARRIVE": return .arrive
        case "TURN_LEFT": return .turnLeft
        case "TURN_RIGHT": return .turnRight
        case "TURN_SLIGHT_LEFT": return .slightLeft
        case "TURN_SLIGHT_RIGHT": return .slightRight
        case "TURN_SHARP_LEFT": return .sharpLeft
        case "TURN_SHARP_RIGHT": return .sharpRight
        case "TURN":
            if slight { return lr(.slightLeft, .slightRight, .straight) }
            if sharp { return lr(.sharpLeft, .sharpRight, .straight) }
            return lr(.turnLeft, .turnRight, .straight)
        case "UTURN", "UTURN_LEFT", "UTURN_RIGHT": return .uturn
        case "STRAIGHT", "CONTINUE", "NAME_CHANGE": return .straight
        case "MERGE", "MERGE_LEFT", "MERGE_RIGHT": return .merge
        case "FORK", "FORK_LEFT", "FORK_RIGHT": return lr(.forkLeft, .forkRight, .straight)
        case "ON_RAMP", "OFF_RAMP", "RAMP", "RAMP_LEFT", "ON_RAMP_LEFT", "OFF_RAMP_LEFT", "RAMP_RIGHT", "ON_RAMP_RIGHT", "OFF_RAMP_RIGHT":
            return lr(.rampLeft, .rampRight, .merge)
        case "KEEP", "KEEP_LEFT", "KEEP_RIGHT": return lr(.keepLeft, .keepRight, .straight)
        default:
            if token?.uppercased().contains("ROUNDABOUT") == true { return .roundabout }
            return lr(.turnLeft, .turnRight, .unknown)
        }
    }

    /// Each turn at its fraction of the step-distance total along the line; arrive pinned to the end.
    static func placeManeuvers(_ ms: [Maneuver], polyline: [LatLng]) -> [Maneuver] {
        guard !ms.isEmpty, polyline.count >= 2 else { return ms }
        let cum = Geo.cumulative(polyline)
        let total = cum.last!
        let stepTotal = max(1, ms.reduce(0) { $0 + $1.distanceMeters })
        var acc = 0.0
        return ms.enumerated().map { i, m in
            let frac = i == ms.count - 1 ? 1 : min(1, max(0, acc / stepTotal))
            acc += m.distanceMeters
            var out = m
            out.alongMeters = total * frac
            out.location = Geo.point(along: polyline, cum: cum, meters: out.alongMeters)
            return out
        }
    }
}
