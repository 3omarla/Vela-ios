import Foundation

/// FOSSGIS OSRM (routing.openstreetmap.de): real turn-by-turn steps from OpenStreetMap.
enum OSRM {
    static let host = "https://routing.openstreetmap.de"

    struct Options {
        var alternatives = false
        /// Indices of [coords] that are stops; the rest are pass-through vias.
        var waypoints: [Int]?
        var bearings: [String]?
        var radiuses: [String]?
        var exclude: [String] = []
    }

    static func route(_ coords: [LatLng], mode: TravelMode, options: Options = Options(), timeout: TimeInterval = 12) async throws -> [Route] {
        let path = coords.map { String(format: "%.6f,%.6f", $0.lng, $0.lat) }.joined(separator: ";")
        var q = "overview=full&geometries=polyline6&steps=true&continue_straight=true"
        if options.alternatives { q += "&alternatives=true" }
        if let w = options.waypoints { q += "&waypoints=" + w.map(String.init).joined(separator: ";") }
        if let b = options.bearings { q += "&bearings=" + b.joined(separator: ";") }
        if let r = options.radiuses { q += "&radiuses=" + r.joined(separator: ";") }
        if !options.exclude.isEmpty && mode == .drive { q += "&exclude=" + options.exclude.joined(separator: ",") }
        let url = "\(host)/\(mode.osrmBackend)/route/v1/driving/\(path)?\(q)"
        let json = PJ(try await OpenHTTP.getJSON(url, timeout: timeout))
        guard (json.raw as? [String: Any])?["code"] as? String == "Ok",
              let routes = (json.raw as? [String: Any])?["routes"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return routes.compactMap { parse($0, mode: mode) }
    }

    private static func parse(_ r: [String: Any], mode: TravelMode) -> Route? {
        guard let geom = r["geometry"] as? String, let distance = r["distance"] as? Double,
              let duration = r["duration"] as? Double, let legs = r["legs"] as? [[String: Any]] else { return nil }
        let line = PolylineCodec.decode(geom, precision: 6)
        guard line.count >= 2 else { return nil }
        var steps: [[String: Any]] = []
        for (li, leg) in legs.enumerated() {
            for s in (leg["steps"] as? [[String: Any]] ?? []) {
                let type = (s["maneuver"] as? [String: Any])?["type"] as? String
                // Interior legs exist only for vias: drop their arrive and depart.
                if type == "arrive" && li < legs.count - 1 { continue }
                if type == "depart" && li > 0 { continue }
                steps.append(s)
            }
        }
        var ms: [Maneuver] = []
        for (i, s) in steps.enumerated() {
            guard let m = s["maneuver"] as? [String: Any], let loc = m["location"] as? [Double], loc.count == 2 else { continue }
            let next = i + 1 < steps.count ? steps[i + 1] : nil
            ms.append(Maneuver(
                type: maneuverType(m), instruction: instruction(s, next: next),
                location: LatLng(loc[1], loc[0]), distanceMeters: s["distance"] as? Double ?? 0,
                road: roadName(s), laneHint: laneHint(s)
            ))
        }
        let summary = legs.compactMap { $0["summary"] as? String }.filter { !$0.isEmpty }.first
        var route = Route(source: .osrm, mode: mode, polyline: line, maneuvers: ms, distanceMeters: distance,
                          durationSeconds: duration, summary: summary)
        RouteIndex.indexManeuvers(&route)
        return route
    }

    static func roadName(_ s: [String: Any]) -> String? {
        let name = (s["name"] as? String)?.nonBlank
        let ref = (s["ref"] as? String)?.nonBlank
        switch (name, ref) {
        case let (n?, r?): return n.contains(r) ? n : "\(n) (\(r.replacingOccurrences(of: ";", with: "/")))"
        case let (n?, nil): return n
        case let (nil, r?): return r.replacingOccurrences(of: ";", with: "/")
        default: return nil
        }
    }

    private static func laneHint(_ s: [String: Any]) -> String? {
        guard let ints = s["intersections"] as? [[String: Any]], let lanes = ints.first?["lanes"] as? [[String: Any]], lanes.count >= 2 else { return nil }
        let valid = lanes.map { $0["valid"] as? Bool ?? false }
        let count = valid.filter { $0 }.count
        guard count > 0, count < lanes.count else { return nil }
        if valid.prefix(count).allSatisfy({ $0 }) { return count == 1 ? "Use the left lane" : "Use the left \(count) lanes" }
        if valid.suffix(count).allSatisfy({ $0 }) { return count == 1 ? "Use the right lane" : "Use the right \(count) lanes" }
        return nil
    }

    static func maneuverType(_ m: [String: Any]) -> ManeuverType {
        let type = m["type"] as? String ?? ""
        let mod = m["modifier"] as? String ?? ""
        func byMod(_ fb: ManeuverType = .straight) -> ManeuverType {
            switch mod {
            case "left": return .turnLeft
            case "right": return .turnRight
            case "slight left": return .slightLeft
            case "slight right": return .slightRight
            case "sharp left": return .sharpLeft
            case "sharp right": return .sharpRight
            case "uturn": return .uturn
            default: return fb
            }
        }
        switch type {
        case "depart": return .depart
        case "arrive": return .arrive
        case "merge": return .merge
        case "on ramp", "off ramp": return mod.contains("left") ? .rampLeft : mod.contains("right") ? .rampRight : .merge
        case "fork": return mod.contains("left") ? .forkLeft : .forkRight
        case "roundabout", "rotary", "roundabout turn", "exit roundabout", "exit rotary": return .roundabout
        case "new name", "continue", "notification":
            if mod.hasPrefix("slight") { return mod.contains("left") ? .keepLeft : .keepRight }
            return byMod()
        default: return byMod()
        }
    }

    private static func ordinal(_ n: Int) -> String {
        ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"][max(0, min(9, n - 1))]
    }

    /// English wording in the spirit of osrm-text-instructions.
    static func instruction(_ s: [String: Any], next: [String: Any]?) -> String {
        let m = s["maneuver"] as? [String: Any] ?? [:]
        let type = m["type"] as? String ?? "turn"
        let mod = m["modifier"] as? String ?? "straight"
        let road = roadName(s)
        let onto = road.map { " onto \($0)" } ?? ""
        let dest = (s["destinations"] as? String)?.nonBlank.map { " toward \($0.components(separatedBy: ",").first!.trimmingCharacters(in: .whitespaces))" } ?? ""
        let exits = (s["exits"] as? String)?.nonBlank.map { "exit \($0.components(separatedBy: ";").first!) " } ?? ""
        let dir: String = {
            switch mod {
            case "uturn": return "Make a U-turn"
            case "straight": return "Continue straight"
            default: return "Turn \(mod)"
            }
        }()
        switch type {
        case "depart":
            let bearing = (m["bearing_after"] as? Double) ?? 0
            let heading = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][Int((bearing + 22.5) / 45) % 8]
            return "Head \(heading)" + (road.map { " on \($0)" } ?? "")
        case "arrive":
            switch mod {
            case "left": return "Your destination is on the left"
            case "right": return "Your destination is on the right"
            default: return "You have arrived at your destination"
            }
        case "new name": return "Continue" + (road.map { " onto \($0)" } ?? "")
        case "continue":
            if mod.hasPrefix("slight") { return "Keep \(mod.contains("left") ? "left" : "right")" + onto + dest }
            if mod == "straight" { return "Continue" + (road.map { " on \($0)" } ?? "") }
            return dir + (road.map { " to stay on \($0)" } ?? "")
        case "merge": return "Merge" + (mod.contains("left") ? " left" : mod.contains("right") ? " right" : "") + onto
        case "on ramp": return "Take the ramp" + (mod.contains("left") ? " on the left" : mod.contains("right") ? " on the right" : "") + onto + dest
        case "off ramp": return "Take \(exits.isEmpty ? "the exit" : exits.trimmingCharacters(in: .whitespaces).capitalizedFirst)" + (mod.contains("left") ? " on the left" : "") + onto + dest
        case "fork": return "Keep \(mod.contains("left") ? "left" : "right") at the fork" + onto + dest
        case "end of road": return "Turn \(mod.contains("left") ? "left" : "right")" + onto
        case "roundabout", "rotary":
            let exit = m["exit"] as? Int
            let name = (s["rotary_name"] as? String).map { " at \($0)" } ?? ""
            let nextRoad = next.flatMap { roadName($0) }.map { " onto \($0)" } ?? onto
            if let exit { return "At the roundabout\(name), take the \(ordinal(exit)) exit" + nextRoad }
            return "Enter the roundabout\(name)" + nextRoad
        case "roundabout turn": return "At the roundabout, \(dir.lowercased())" + onto
        case "exit roundabout", "exit rotary": return "Exit the roundabout" + onto
        default: return dir + onto
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Nominatim reverse geocoding: names a dropped pin.
enum Nominatim {
    static func reverse(_ p: LatLng) async -> Place {
        var place = Place(id: String(format: "pin:%.6f,%.6f", p.lat, p.lng), name: "Dropped pin", location: p)
        let url = String(format: "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=%.6f&lon=%.6f&zoom=18&addressdetails=1", p.lat, p.lng)
        guard let json = try? await OpenHTTP.getJSON(url) as? [String: Any] else { return place }
        let addr = json["address"] as? [String: String] ?? [:]
        let street = [addr["house_number"], addr["road"]].compactMap { $0 }.joined(separator: " ")
        if let name = (json["name"] as? String)?.nonBlank { place.name = name } else if !street.isEmpty { place.name = street }
        let city = addr["city"] ?? addr["town"] ?? addr["village"] ?? addr["suburb"]
        place.address = [street.nonBlank, city, addr["state"], addr["postcode"]].compactMap { $0 }.joined(separator: ", ").nonBlank
        place.category = (json["type"] as? String).flatMap { $0 == "yes" ? nil : $0.replacingOccurrences(of: "_", with: " ").capitalized }
        return place
    }
}
