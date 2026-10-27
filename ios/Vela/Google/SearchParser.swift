import Foundation

/// Parses the `/search?tbm=map` response (core SearchParser.kt).
enum SearchParser {
    static func parse(query: String, root: PJ, near: LatLng?, paths: [String: [Int]] = Calibration.paths) throws -> SearchResult {
        guard root.isArray else { throw CalibrationNeeded(detail: "search: response not a JSON array") }
        let listed = root.at(paths["results"]).arr ?? []
        let focused = listed.isEmpty
        guard let entries = (listed.isEmpty ? nil : listed)
                ?? atThisPlaceEntries(root, paths)
                ?? singleResultEntry(root, paths)
                ?? findResultsArray(root, paths) else {
            return SearchResult(query: query, places: [])
        }
        var places = entries.compactMap { toPlace($0, near: near, paths: paths) }
        if focused && places.count == 1, let also = root.at(paths["alsoSearched"]).arr {
            let others = also.compactMap { $0.isArray ? toPlace($0, near: near, paths: paths) : nil }
            places += otherBranches(query: query, also: others, focus: places[0])
        }
        if near != nil {
            // Nearest first in 120 m buckets; within a bucket, the more-reviewed place leads.
            places.sort { a, b in
                let ba = a.distanceMeters.map { Int($0 / 120) } ?? .max
                let bb = b.distanceMeters.map { Int($0 / 120) } ?? .max
                if ba != bb { return ba < bb }
                if (a.reviewCount ?? 0) != (b.reviewCount ?? 0) { return (a.reviewCount ?? 0) > (b.reviewCount ?? 0) }
                return (a.distanceMeters ?? .greatestFiniteMagnitude) < (b.distanceMeters ?? .greatestFiniteMagnitude)
            }
        }
        return SearchResult(query: query, places: places, focusedSingle: focused && places.count == 1)
    }

    private static func nameKey(_ t: String) -> String { t.lowercased().filter { $0.isLetter || $0.isNumber } }

    static func isBranch(query: String, focus: Place, p: Place) -> Bool {
        let q = nameKey(query)
        guard q.count >= 3 else { return false }
        let n = nameKey(p.name)
        if n.isEmpty { return false }
        return n.contains(q) || (n.count >= 4 && q.contains(n)) || n == nameKey(focus.name)
    }

    static func otherBranches(query: String, also: [Place], focus: Place) -> [Place] {
        also.filter { p in
            isBranch(query: query, focus: focus, p: p) && (p.featureId == nil || p.featureId != focus.featureId) &&
                p.location.distance(to: focus.location) > 30
        }
    }

    private static func wrap(_ node: PJ) -> PJ { PJ([NSNull(), node.raw ?? NSNull()]) }

    private static func singleResultEntry(_ root: PJ, _ paths: [String: [Int]]) -> [PJ]? {
        let node = root.at(paths["single"])
        guard !node.isNil else { return nil }
        let entry = wrap(node)
        return entry.at(paths["name"]).str == nil ? nil : [entry]
    }

    private static func atThisPlaceEntries(_ root: PJ, _ paths: [String: [Int]]) -> [PJ]? {
        guard let list = root.at(paths["atThisPlace"]).arr else { return nil }
        let entries = list.compactMap { e -> PJ? in
            let node = e.at(0)
            guard !node.isNil else { return nil }
            let entry = wrap(node)
            return entry.at(paths["name"]).str == nil ? nil : entry
        }
        return entries.isEmpty ? nil : entries
    }

    private static func findResultsArray(_ root: PJ, _ paths: [String: [Int]]) -> [PJ]? {
        root.arr?.compactMap(\.arr).filter { !$0.isEmpty && $0[0].at(paths["name"]).str != nil }.max { $0.count < $1.count }
    }

    static func toPlace(_ entry: PJ, near: LatLng?, paths: [String: [Int]]) -> Place? {
        func f(_ key: String) -> PJ { entry.at(paths[key]) }
        guard let name = f("name").str, let lat = f("lat").dbl, let lng = f("lng").dbl else { return nil }
        let loc = LatLng(lat, lng)
        let rich = f("statusRich").str, s118 = f("status118").str
        let status = rich ?? s118 ?? f("openStatus").str
        let componentsJoined = f("addressComponents").arr?.compactMap(\.str)
            .filter { $0.caseInsensitiveCompare(name) != .orderedSame }.joined(separator: ", ").nonBlank
        let address = (f("address").str ?? componentsJoined ?? f("addressComponents").at(0).str).map { stripNamePrefix($0, name: name) }
        var p = Place(id: f("featureId").str ?? "g:\(name.hashValue):\(Int(lat * 1e4))", name: name, location: loc)
        p.category = f("category").str
        p.address = address
        p.rating = f("rating").dbl
        p.reviewCount = f("reviewCount").int
        p.priceText = f("priceText").str
        p.fuelPrice = f("fuelPrice").str?.trimmingCharacters(in: .whitespaces).nonBlank.flatMap { s in
            s.contains(where: \.isNumber) && s.count <= 24 ? s : nil
        }
        p.website = f("website").str
        p.actionUrl = f("actionUrl").str.flatMap { $0.lowercased().hasPrefix("http") ? $0 : nil }
        p.actionLabel = f("actionLabel").str?.nonBlank.flatMap { $0.count <= 30 ? $0 : nil }
        p.phone = f("phone").str
        p.openNow = parseOpenNow(status)
        p.statusText = status
        p.permanentlyClosed = f("closedFlag").int == 1 || [s118, rich, f("openStatus").str].contains { $0?.localizedCaseInsensitiveContains("Permanently") == true }
        p.temporarilyClosed = isTemporarilyClosed([s118, rich, f("openStatus").str])
        let h203 = readHours(f("hours203")), h118 = readHours(f("hours118"))
        p.hours = (rich == nil && s118 != nil) ? (h118.isEmpty ? h203 : h118) : (h203.isEmpty ? h118 : h203)
        p.departments = parseDepartments(f("departments"), storeName: name)
        p.photoUrls = parsePhotos(entry, paths)
        p.featuredReview = f("featuredReview").str?.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”\n")).nonBlank
        p.featureId = f("featureId").str
        p.placeId = f("placeId").str
        p.about = (f("about").arr ?? []).compactMap { s in
            guard let title = s.at(1).str else { return nil }
            let items = (s.at(2).arr ?? []).compactMap { $0.at(1).str?.nonBlank }
            return items.isEmpty ? nil : AboutSection(title: title, items: items)
        }
        p.editorialSummary = f("editorialSummary").str?.nonBlank
        p.distanceMeters = near.map { $0.distance(to: loc) }
        return p
    }

    private static func parsePhotos(_ entry: PJ, _ paths: [String: [Int]]) -> [String] {
        var urls: [String] = []
        func add(_ u: String?) {
            guard let u, u.contains("googleusercontent") else { return }
            let sized = u.replacing(#"=w\d+-h\d+.*$"#, with: "=w800-h600")
            if !urls.contains(sized) { urls.append(sized) }
        }
        entry.at(paths["photos"]).arr?.forEach { add($0.at(6, 0).str) }
        entry.at(1, 204, 0).arr?.forEach { add($0.at(1, 2, 0, 0).str) }
        return Array(urls.prefix(12))
    }

    static func stripNamePrefix(_ addr: String, name: String) -> String {
        guard !name.isEmpty, addr.lowercased().hasPrefix(name.lowercased()) else { return addr }
        let rest = addr.dropFirst(name.count)
        if let c = rest.first, c.isLetter || c.isNumber { return addr }
        let after = rest.drop { $0 == " " || $0 == "\u{00A0}" }
        if let c = after.first, !c.isNumber, !",·–-".contains(c) { return addr }
        let out = after.drop { ",·-– \u{00A0}".contains($0) }
        return out.isEmpty ? addr : String(out)
    }

    private static let tempClosedWords = ["Temporarily", "temporairement", "Vorübergehend", "temporalmente", "temporaneamente",
                                          "temporariamente", "Tijdelijk", "Временно", "Tymczasowo", "Tillfälligt", "Тимчасово", "זמנית", "temporar"]

    static func isTemporarilyClosed(_ status: [String?]) -> Bool {
        status.contains { s in s.map { s in tempClosedWords.contains { s.localizedCaseInsensitiveContains($0) } } ?? false }
    }

    /// Closed words are tested first: several languages' opening phrases start like their open words.
    private static let closedWords: [String: [String]] = [
        "en": ["Closed", "Opens", "Opening", "Temporarily", "Permanently"],
        "fr": ["Fermé", "Ouvre", "Définitivement"],
        "de": ["Geschlossen", "Öffnet", "Vorübergehend", "Dauerhaft"],
        "es": ["Cerrado", "Abre"], "it": ["Chiuso", "Apre"], "pt": ["Fechado", "Abre"],
        "nl": ["Gesloten", "Opent", "Tijdelijk", "Definitief"],
        "ru": ["Закрыто", "Откроется", "Временно"], "pl": ["Zamknięte", "Otwarcie", "Tymczasowo"],
        "sv": ["Stängt", "Öppnar", "Tillfälligt"], "uk": ["Зачинено", "Відчиниться", "Тимчасово"],
        "hu": ["Zárva", "Nyitás", "Hamarosan zár", "Végleg bezárt", "Ideiglenesen zárva"],
        "ro": ["Închis", "Deschide", "Se deschide"],
        "zh": ["已打烊", "已歇業", "开始营业", "開始營業", "尚未营业", "尚未營業", "暂停营业", "暫停營業", "永久停业", "永久歇業", "休息中"],
        "ja": ["営業時間外", "営業開始", "臨時休業", "閉業", "休業"],
        "he": ["סגור", "נפתח", "ייפתח", "המקום סגור"],
    ]

    private static let openWords: [String: [String]] = [
        "en": ["Open", "Closes", "Closing"], "fr": ["Ouvert", "Ferme"], "de": ["Geöffnet", "Schließt"],
        "es": ["Abierto", "Cierra"], "it": ["Aperto", "Chiude"], "pt": ["Aberto", "Fecha"],
        "nl": ["Geopend", "Open", "Sluit"], "ru": ["Открыто", "Закроется", "Закрывается"],
        "pl": ["Otwarte", "Zamknięcie"], "sv": ["Öppet", "Stänger"], "uk": ["Відчинено", "Зачиняється"],
        "hu": ["Nyitva", "Zárás", "Hamarosan nyit"], "ro": ["Deschis", "Închide", "Se închide"],
        "zh": ["营业中", "營業中", "打烊", "營業至", "营业至"], "ja": ["営業中", "営業終了", "まもなく営業終了"],
        "he": ["פתוח", "נסגר", "המקום פתוח"],
    ]

    static var statusLangs: Set<String> { Set(closedWords.keys) }

    static func parseOpenNow(_ status: String?, lang: String = Locale.current.language.languageCode?.identifier ?? "en") -> Bool? {
        guard let s = status?.nonBlank else { return nil }
        let closed = closedWords[lang] ?? closedWords["en"]!
        let open = openWords[lang] ?? openWords["en"]!
        if closed.contains(where: { s.hasPrefix($0) }) { return false }
        if open.contains(where: { s.hasPrefix($0) }) { return true }
        return nil
    }

    static func readHours(_ days: PJ) -> [String] {
        (days.arr ?? []).compactMap { day in
            guard let name = day.at(0).str,
                  let hrs = (day.at(3).arr ?? []).compactMap({ $0.at(0).str?.nonBlank }).joined(separator: ", ").nonBlank else { return nil }
            if let note = day.at(6, 1).str?.nonBlank { return "\(name): \(hrs) · \(dedupeHolidayLabel(note))" }
            return "\(name): \(hrs)"
        }
    }

    static func dedupeHolidayLabel(_ note: String) -> String {
        let parts = note.split(whereSeparator: { "/·•|".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count >= 2, parts.allSatisfy({ $0.caseInsensitiveCompare(parts[0]) == .orderedSame }) { return parts[0] }
        return note.trimmingCharacters(in: .whitespaces)
    }

    private static func parseDepartments(_ list: PJ, storeName: String) -> [Department] {
        (list.arr ?? []).compactMap { dep in
            guard let raw = dep.at(0).str?.nonBlank else { return nil }
            var name = raw
            if raw.lowercased().hasPrefix(storeName.lowercased()) && raw.count > storeName.count {
                name = String(raw.dropFirst(storeName.count)).nonBlank ?? raw
            }
            let hours = readHours(dep.at(3, 0))
            let status = dep.at(3, 1, 4, 0).str?.nonBlank
            if hours.isEmpty && status == nil { return nil }
            return Department(name: name, hours: hours, statusText: status, openNow: parseOpenNow(status))
        }
    }
}

/// Google Maps' search-as-you-type answer (core SuggestParser.kt).
enum SuggestParser {
    static func parse(_ body: String, paths: [String: [Int]] = Calibration.suggestPaths) -> SuggestResult {
        guard let payload = unwrap(body), let root = PJ.parse(payload), let rows = root.at(paths["rows"]).arr else {
            return SuggestResult(places: [], queries: [])
        }
        var places: [Place] = [], queries: [String] = []
        for row in rows {
            guard let block = row.arr?.first(where: { el in el.arr?.first?.arr?.first?.str != nil }) else { continue }
            func s(_ k: String) -> String? { block.at(paths[k]).str?.nonBlank }
            guard let title = s("title") else { continue }
            let primary = s("primary") ?? title
            let lat = block.at(paths["lat"]).dbl ?? block.at(paths["lat2"]).dbl
            let lng = block.at(paths["lng"]).dbl ?? block.at(paths["lng2"]).dbl
            guard let lat, let lng else { queries.append(title); continue }
            let fid = s("featureId").flatMap { $0.firstMatch(#"^0x[0-9a-f]+:0x[0-9a-f]+$"#) != nil ? $0 : nil }
            var p = Place(id: fid ?? String(format: "suggest:%.5f,%.5f", lat, lng), name: primary, location: LatLng(lat, lng))
            p.address = s("secondary").flatMap { $0 == primary ? nil : $0 }
            p.featureId = fid
            places.append(p)
        }
        return SuggestResult(places: places, queries: queries)
    }

    /// The `d` string out of the first `{"c":0,"d":"..."}` object.
    static func unwrap(_ body: String) -> String? {
        let chars = Array(body)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, i = start, end: Int?
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" { i += 1 } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
            i += 1
        }
        guard let end, let data = String(chars[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["d"] as? String
    }
}
