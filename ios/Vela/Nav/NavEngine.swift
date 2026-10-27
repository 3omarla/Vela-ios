import Foundation

/// One fix projected onto the route: progress, the step, distances and the events to act on
/// (core NavEngine.kt; constants from SPEC 4.6).
struct NavEngine {
    struct Fix {
        var location: LatLng
        var accuracy: Double?
        var speed: Double?      // m/s, nil when unknown
        var course: Double?     // degrees, nil when unknown
    }

    enum Event: Equatable {
        case prompt(String)
        case offRoute
        case arrived
    }

    let route: Route
    let cum: [Double]
    let total: Double

    private(set) var progress: Double = 0
    private(set) var stepIndex = 0
    private(set) var offHits = 0
    private(set) var snapped: LatLng
    private(set) var offDistance: Double = 0
    private var reacquireHits = 0
    private var spoken: Set<String> = []
    private(set) var arrived = false

    static let windowBehind = 60.0, windowAhead = 600.0
    static let anchorPenalty = 0.02
    static let onRoute = 60.0
    static let reacquireJump = 1_500.0
    static let offRouteHits = 3
    static let headingOffDeg = 60.0
    static let destZone = 150.0
    static let arriveRadius = 25.0

    init(route: Route) {
        self.route = route
        cum = Geo.cumulative(route.polyline)
        total = cum.last ?? 0
        snapped = route.polyline.first ?? LatLng(0, 0)
        stepIndex = route.maneuvers.first?.type == .depart && route.maneuvers.count > 1 ? 1 : 0
    }

    var currentManeuver: Maneuver? { stepIndex < route.maneuvers.count ? route.maneuvers[stepIndex] : nil }
    var nextManeuver: Maneuver? { stepIndex + 1 < route.maneuvers.count ? route.maneuvers[stepIndex + 1] : nil }
    var distanceToManeuver: Double { max(0, (currentManeuver?.alongMeters ?? total) - progress) }
    var remainingMeters: Double { max(0, total - progress) }

    /// Remaining time, scaled from the trip's best duration by the share of distance left.
    var remainingSeconds: Double {
        guard total > 0 else { return 0 }
        return route.bestDuration * remainingMeters / total
    }

    var bearingHere: Double { Geo.bearing(along: route.polyline, cum: cum, meters: progress) }

    static func corridor(mode: TravelMode, accuracy: Double?) -> (corridor: Double, far: Double, movingFloor: Double) {
        let acc = min(40, max(3, accuracy ?? 12))
        switch mode {
        case .drive: return (min(70, max(24, 18 + 2.0 * acc)), min(110, 2 * min(70, max(24, 18 + 2.0 * acc))), 2.0)
        case .bicycle: return (min(55, max(18, 12 + 1.9 * acc)), min(75, 2 * min(55, max(18, 12 + 1.9 * acc))), 1.0)
        case .walk: return (min(50, max(15, 8 + 1.8 * acc)), min(60, 2 * min(50, max(15, 8 + 1.8 * acc))), 0.6)
        }
    }

    mutating func update(_ fix: Fix) -> [Event] {
        guard !arrived, route.polyline.count >= 2 else { return [] }
        var events: [Event] = []
        let line = route.polyline

        // Progress: the window from 60 m behind to 600 m ahead, scored by distance plus a small
        // penalty per meter from the progress so far, so an out-and-back road resolves.
        func best(in segs: ClosedRange<Int>) -> Geo.Projection? {
            var bestP: Geo.Projection?, bestScore = Double.infinity
            for i in segs {
                guard let p = Geo.project(fix.location, on: line, cum: cum, segments: i...i) else { continue }
                let score = p.offMeters + Self.anchorPenalty * abs(p.alongMeters - progress)
                if score < bestScore { bestScore = score; bestP = p }
            }
            return bestP
        }
        let window = Geo.segments(cum: cum, from: max(0, progress - Self.windowBehind), to: progress + Self.windowAhead)
        var proj = best(in: window)
        if proj == nil || proj!.offMeters > Self.onRoute {
            if let whole = best(in: 0...(line.count - 2)), whole.offMeters <= Self.onRoute {
                if abs(whole.alongMeters - progress) > Self.reacquireJump {
                    reacquireHits += 1
                    if reacquireHits >= 3 { proj = whole; reacquireHits = 0 }
                } else { proj = whole; reacquireHits = 0 }
            }
        } else { reacquireHits = 0 }
        guard let p = proj else { return [] }
        offDistance = p.offMeters
        if p.offMeters <= Self.onRoute { progress = p.alongMeters; snapped = p.point }

        // Off route.
        let c = Self.corridor(mode: route.mode, accuracy: fix.accuracy)
        let moving = (fix.speed ?? 0) >= c.movingFloor
        let headingOff = moving && fix.course.map { Geo.angleDiff($0, bearingHere) > Self.headingOffDeg } == true
        if p.offMeters > c.far && moving { offHits += 2 }
        else if p.offMeters > c.corridor && (moving || p.offMeters > c.far) { offHits += 1 }
        else if headingOff { offHits += p.offMeters > c.corridor / 4 ? 2 : 1 }
        else if p.offMeters <= c.corridor { offHits = 0 }
        let nearDest = remainingMeters < Self.destZone && fix.location.distance(to: route.polyline.last!) < Self.destZone
        if offHits >= Self.offRouteHits && !nearDest {
            events.append(.offRoute)
            return events
        }

        // Arrival.
        if remainingMeters < Self.arriveRadius || (nearDest && fix.location.distance(to: route.polyline.last!) < Self.arriveRadius) {
            arrived = true
            events.append(.arrived)
            return events
        }

        // Advance past maneuvers already reached.
        while stepIndex < route.maneuvers.count - 1 && route.maneuvers[stepIndex].alongMeters <= progress + 5 {
            stepIndex += 1
        }

        // Prompts at speed-scaled distances, each band once per step.
        if offHits == 0, let m = currentManeuver {
            let v = max(fix.speed ?? 0, route.mode == .drive ? 8 : 1.4)
            let far = roundTo50(max(route.mode == .drive ? 400 : 150, v * 35))
            let near = roundTo50(max(route.mode == .drive ? 150 : 40, v * 10))
            let now = min(90, max(25, v * 2.5))
            let d = distanceToManeuver
            let key = "\(stepIndex)"
            if d <= now, spoken.insert(key + "now").inserted {
                spoken.insert(key + "near"); spoken.insert(key + "far")
                events.append(.prompt(Self.nowPhrase(m, then: nextManeuver)))
            } else if d <= near, d > now, spoken.insert(key + "near").inserted {
                spoken.insert(key + "far")
                events.append(.prompt("In \(Units.spoken(d)), \(Self.lowerFirst(m.instruction))"))
            } else if d <= far, d > near, d > 300 || route.mode != .drive, spoken.insert(key + "far").inserted {
                events.append(.prompt("In \(Units.spoken(d)), \(Self.lowerFirst(m.instruction))"))
            }
        }
        return events
    }

    private func roundTo50(_ v: Double) -> Double { (v / 50).rounded() * 50 }

    static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// The turn itself, chained with the next one when it follows close behind.
    static func nowPhrase(_ m: Maneuver, then next: Maneuver?) -> String {
        guard let next, next.type != .arrive || next.alongMeters - m.alongMeters < 100,
              next.alongMeters - m.alongMeters < 120 else { return m.instruction }
        return "\(m.instruction), then \(lowerFirst(next.instruction))"
    }

    mutating func markDepartSpoken() { spoken.insert("depart") }
}
