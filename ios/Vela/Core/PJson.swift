import Foundation

/// Null-safe positional access over Google's field-name-free JSON arrays (core GoogleResponse.kt).
/// Any wrong or missing step yields nil rather than throwing: Google inserts elements mid-array
/// without notice.
struct PJ {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw is NSNull ? nil : raw }

    static let guards = [")]}'\n", ")]}',\n", ")]}'", ")]}", "while(1);", "for(;;);"]

    static func strip(_ body: String) -> String {
        for g in guards where body.hasPrefix(g) {
            return String(body.dropFirst(g.count)).trimmingCharacters(in: .newlines)
        }
        return body
    }

    static func parse(_ body: String) -> PJ? {
        guard let data = strip(body).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return PJ(obj)
    }

    func at(_ path: Int...) -> PJ { at(path) }

    func at(_ path: [Int]?) -> PJ {
        guard let path else { return PJ(nil) }
        var cur: Any? = raw
        for i in path {
            guard let a = cur as? [Any], i >= 0, i < a.count else { return PJ(nil) }
            cur = a[i]
        }
        return PJ(cur)
    }

    var arr: [PJ]? { (raw as? [Any]).map { $0.map(PJ.init) } }
    var isArray: Bool { raw is [Any] }
    var isNil: Bool { raw == nil }

    var str: String? {
        guard let s = raw as? String else { return nil }
        return s
    }

    var dbl: Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    var int: Int? { dbl.map { Int($0) } }
    var int64: Int64? { (raw as? NSNumber)?.int64Value }

    /// Every string in the subtree, depth first.
    func strings() -> [String] {
        var out: [String] = []
        func walk(_ v: Any?) {
            if let a = v as? [Any] { a.forEach(walk) } else if let s = v as? String { out.append(s) }
        }
        walk(raw)
        return out
    }

    /// The subtree serialized, for regex scans over a whole entry.
    var serialized: String {
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let d = try? JSONSerialization.data(withJSONObject: raw) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
}

extension String {
    var nonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Query-component encoding as OkHttp/URLEncoder would (space as %20, ! kept encoded).
    var urlEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    func firstMatch(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: self).map { String(self[$0]) } ?? ""
        }
    }

    func replacing(_ pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }
}

struct CalibrationNeeded: Error, LocalizedError {
    let detail: String
    var errorDescription: String? { "Google changed its response (\(detail)). Search may be degraded until Vela is recalibrated." }
}
