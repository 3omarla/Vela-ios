import Foundation

enum Geo {
    static let earthRadius = 6_371_008.8

    static func distance(_ a: LatLng, _ b: LatLng) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dp = (b.lat - a.lat) * .pi / 180, dl = (b.lng - a.lng) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Initial bearing a to b, degrees 0..360.
    static func bearing(_ a: LatLng, _ b: LatLng) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dl = (b.lng - a.lng) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    static func interpolate(_ a: LatLng, _ b: LatLng, _ f: Double) -> LatLng {
        LatLng(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f)
    }

    /// Cumulative meters at each vertex.
    static func cumulative(_ line: [LatLng]) -> [Double] {
        var out = [Double](repeating: 0, count: line.count)
        for i in line.indices.dropFirst() { out[i] = out[i - 1] + distance(line[i - 1], line[i]) }
        return out
    }

    static func length(_ line: [LatLng]) -> Double { cumulative(line).last ?? 0 }

    static func point(along line: [LatLng], cum: [Double], meters: Double) -> LatLng {
        guard let first = line.first else { return LatLng(0, 0) }
        if meters <= 0 { return first }
        guard let total = cum.last, meters < total else { return line.last! }
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= meters { lo = mid } else { hi = mid }
        }
        let seg = cum[hi] - cum[lo]
        return interpolate(line[lo], line[hi], seg == 0 ? 0 : (meters - cum[lo]) / seg)
    }

    static func bearing(along line: [LatLng], cum: [Double], meters: Double) -> Double {
        guard line.count >= 2 else { return 0 }
        var i = 0
        while i < cum.count - 2 && cum[i + 1] < meters { i += 1 }
        return bearing(line[i], line[i + 1])
    }

    struct Projection {
        var point: LatLng
        var alongMeters: Double
        var offMeters: Double
        var segment: Int
    }

    /// Nearest point of segment i of [line] to p, in a local flat frame around p.
    static func project(_ p: LatLng, on line: [LatLng], cum: [Double], segments: ClosedRange<Int>) -> Projection? {
        guard line.count >= 2 else { return nil }
        let kx = cos(p.lat * .pi / 180) * 111_320.0, ky = 110_540.0
        var best: Projection?
        for i in segments where i >= 0 && i < line.count - 1 {
            let a = line[i], b = line[i + 1]
            let ax = (a.lng - p.lng) * kx, ay = (a.lat - p.lat) * ky
            let bx = (b.lng - p.lng) * kx, by = (b.lat - p.lat) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / len2))
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            if best == nil || d < best!.offMeters {
                best = Projection(point: interpolate(a, b, t), alongMeters: cum[i] + (cum[i + 1] - cum[i]) * t, offMeters: d, segment: i)
            }
        }
        return best
    }

    /// Segment index range covering [from, to] meters along the line.
    static func segments(cum: [Double], from: Double, to: Double) -> ClosedRange<Int> {
        let n = cum.count - 2
        guard n >= 0 else { return 0...0 }
        var lo = 0
        while lo < n && cum[lo + 1] < from { lo += 1 }
        var hi = lo
        while hi < n && cum[hi] < to { hi += 1 }
        return lo...hi
    }
}

extension LatLng {
    func distance(to other: LatLng) -> Double { Geo.distance(self, other) }
}

enum PolylineCodec {
    static func decode(_ encoded: String, precision: Int = 5) -> [LatLng] {
        let scale = pow(10.0, Double(precision))
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat: Int64 = 0, lng: Int64 = 0
        var path: [LatLng] = []
        func next() -> Int64? {
            var shift: Int64 = 0, result: Int64 = 0, b: Int64
            repeat {
                guard index < bytes.count else { return nil }
                b = Int64(bytes[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }
        while index < bytes.count {
            guard let dlat = next(), let dlng = next() else { break }
            lat += dlat; lng += dlng
            path.append(LatLng(Double(lat) / scale, Double(lng) / scale))
        }
        return path
    }
}

enum Units {
    static var metric: Bool { Locale.current.measurementSystem == .metric }

    static func distance(_ m: Double) -> String {
        if metric {
            if m < 950 { return "\(Int((m / 10).rounded() * 10)) m" }
            return String(format: m < 9_950 ? "%.1f km" : "%.0f km", m / 1000)
        }
        let ft = m * 3.28084
        if ft < 1000 { return "\(Int((ft / 50).rounded() * 50)) ft" }
        let mi = m / 1609.344
        return String(format: mi < 9.95 ? "%.1f mi" : "%.0f mi", mi)
    }

    /// Words for the voice: "400 feet", "1.5 miles", "300 meters".
    static func spoken(_ m: Double) -> String {
        if metric {
            if m < 950 { return "\(Int((m / 50).rounded() * 50)) meters" }
            let km = (m / 100).rounded() / 10
            return km == 1 ? "1 kilometer" : "\(fmt(km)) kilometers"
        }
        let ft = m * 3.28084
        if ft < 1000 { return "\(Int((ft / 100).rounded() * 100)) feet" }
        let mi = (m / 160.9344).rounded() / 10
        if mi == 0.5 { return "half a mile" }
        return mi == 1 ? "1 mile" : "\(fmt(mi)) miles"
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func duration(_ s: Double) -> String {
        let mins = Int((s / 60).rounded())
        if mins < 60 { return "\(max(1, mins)) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static func arrival(after s: Double) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: Date().addingTimeInterval(s))
    }
}
