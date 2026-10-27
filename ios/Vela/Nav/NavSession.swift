import Foundation
import CoreLocation
import Combine
import UIKit

/// A drive in progress: feeds fixes to the engine, speaks, reroutes and rechecks traffic
/// (core NavSession.kt, reduced).
@MainActor
final class NavSession: ObservableObject {
    @Published private(set) var engine: NavEngine
    @Published private(set) var rerouting = false
    @Published var muted = false { didSet { VoiceGuide.shared.muted = muted } }
    @Published private(set) var arrived = false
    @Published private(set) var speedMps: Double = 0

    let destination: Place
    let prefs: RoutePrefs
    var onEnd: (() -> Void)?

    private var bag = Set<AnyCancellable>()
    private var lastReroute = Date.distantPast
    private var recheckTimer: Timer?
    private var lastFix: CLLocation?

    /// How often a drive asks Google again for traffic on the road ahead.
    static let recheckInterval: TimeInterval = 120

    init(route: Route, destination: Place, prefs: RoutePrefs) {
        engine = NavEngine(route: route)
        self.destination = destination
        self.prefs = prefs
        VoiceGuide.shared.muted = muted
    }

    var route: Route { engine.route }

    func start() {
        let first = engine.currentManeuver.map { m in
            "Starting route to \(destination.name). \(engine.distanceToManeuver > 30 ? "In \(Units.spoken(engine.distanceToManeuver)), " : "")\(NavEngine.lowerFirst(m.instruction))"
        } ?? "Starting route to \(destination.name)"
        VoiceGuide.shared.speak(first)
        LocationService.shared.fixes.sink { [weak self] l in self?.onLocation(l) }.store(in: &bag)
        if route.mode == .drive {
            recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.recheck() }
            }
        }
    }

    func stop() {
        bag.removeAll()
        recheckTimer?.invalidate()
        recheckTimer = nil
    }

    private func onLocation(_ l: CLLocation) {
        // Guidance takes fixes of 50 m or better.
        guard l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 50, !arrived else { return }
        lastFix = l
        let speed = l.speed >= 0 ? (l.speed < 3 && l.horizontalAccuracy > 30 ? 0 : l.speed) : nil
        speedMps = speed ?? 0
        let fix = NavEngine.Fix(location: LatLng(l.coordinate), accuracy: l.horizontalAccuracy, speed: speed,
                                course: l.course >= 0 && (speed ?? 0) > 1 ? l.course : nil)
        var e = engine
        let events = e.update(fix)
        engine = e
        #if DEBUG
        vlog.info("nav: progress \(Int(e.progress)) / \(Int(e.total)) m, step \(e.stepIndex) in \(Int(e.distanceToManeuver)) m, off \(Int(e.offDistance)) m, hits \(e.offHits), events \(events.count)")
        #endif
        for ev in events {
            switch ev {
            case .prompt(let text):
                VoiceGuide.shared.speak(text)
            case .arrived:
                arrived = true
                VoiceGuide.shared.speak(route.maneuvers.last?.instruction ?? "You have arrived")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                stop()
            case .offRoute:
                Task { await reroute(from: l) }
            }
        }
    }

    private func reroute(from l: CLLocation) async {
        guard !rerouting, Date().timeIntervalSince(lastReroute) > 6 else { return }
        rerouting = true
        lastReroute = Date()
        defer { rerouting = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let fresh = try? await RouteService.routes(from: LatLng(l.coordinate), to: destination.location,
                                                         mode: route.mode, prefs: prefs, urgent: true).first else { return }
        engine = NavEngine(route: fresh)
        VoiceGuide.shared.speak("Rerouting. " + (engine.currentManeuver.map { "In \(Units.spoken(engine.distanceToManeuver)), \(NavEngine.lowerFirst($0.instruction))" } ?? ""))
    }

    /// Asks Google again from here; a route at least 2 minutes and 10% faster replaces this one.
    private func recheck() async {
        guard !rerouting, !arrived, let l = lastFix, engine.remainingMeters > 2_000 else { return }
        guard let fresh = try? await RouteService.routes(from: LatLng(l.coordinate), to: destination.location,
                                                         mode: route.mode, prefs: prefs, urgent: true).first else { return }
        let current = engine.remainingSeconds
        let saving = current - fresh.bestDuration
        if saving > 120 && saving > current * 0.1 {
            engine = NavEngine(route: fresh)
            VoiceGuide.shared.speak("Found a faster route, saving \(Int(saving / 60)) minutes.")
        }
    }

    var eta: String { Units.arrival(after: engine.remainingSeconds) }
}
