import Foundation
import CoreLocation
import Combine
import SwiftUI
import os

let vlog = Logger(subsystem: "com.myomar.vela", category: "app")

enum Sheet: Equatable {
    case none, results, place, directions, navigating, saved
}

/// A request for the map camera, consumed once by the map view.
struct CameraRequest: Equatable {
    enum Kind: Equatable {
        case center(LatLng, zoom: Double?)
        case fit([LatLng])
        case follow
    }
    let id = UUID()
    let kind: Kind
}

@MainActor
final class AppModel: ObservableObject {
    // Search
    @Published var query = ""
    @Published var suggestions = SuggestResult(places: [], queries: [])
    @Published var results: [Place] = []
    @Published var searching = false
    @Published var searchFocused = false

    // Place
    @Published var selected: Place?

    // Directions
    @Published var sheet: Sheet = .none
    @Published var mode: TravelMode = .drive
    @Published var routes: [Route] = []
    @Published var routeIndex = 0
    @Published var loadingRoutes = false
    @Published var origin: Place?
    @Published var destination: Place?
    @Published var prefs: RoutePrefs = Store.load("route_prefs") ?? RoutePrefs() {
        didSet { Store.save(prefs, "route_prefs") }
    }

    // Navigation
    @Published var nav: NavSession?

    // Map
    @Published var camera: CameraRequest?
    @Published var mapCenter = LatLng(37.7749, -122.4194)
    @Published var mapSpanMeters = 20_000.0

    // Saved
    @Published var lists: [SavedList] = SavedList.loadAll() {
        didSet { Store.save(lists, "saved_lists") }
    }
    @Published var home: Place? = Store.load("home_place") {
        didSet { Store.save(home, "home_place") }
    }
    @Published var work: Place? = Store.load("work_place") {
        didSet { Store.save(work, "work_place") }
    }
    /// Home or Work waiting to be chosen in the Saved tab's place picker.
    @Published var pickingShortcut: Shortcut?
    @Published var recents: [Place] = Store.load("recent_places") ?? [] {
        didSet { Store.save(recents, "recent_places") }
    }

    /// A passing notice, shown as a banner that clears itself; never a modal alert, which SwiftUI
    /// cannot show over an open sheet and which then fired late and broke the screen state.
    @Published var errorMessage: String? {
        didSet {
            guard let msg = errorMessage else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if errorMessage == msg { errorMessage = nil }
            }
        }
    }
    /// Why the directions sheet has no routes, shown inside it.
    @Published var routeNote: String?

    let location = LocationService.shared
    private var suggestTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    init() {
        location.start()
        location.$location.compactMap { $0 }.first().sink { [weak self] l in
            self?.camera = CameraRequest(kind: .center(LatLng(l.coordinate), zoom: 14))
        }.store(in: &bag)
        // Directions opened before the first fix: route from here as soon as one arrives.
        location.$location.compactMap { $0 }.sink { [weak self] _ in
            guard let self, self.sheet == .directions, self.origin == nil, self.routes.isEmpty, !self.loadingRoutes,
                  self.routeNote == Self.needStart else { return }
            self.fetchRoutes()
        }.store(in: &bag)
    }

    var userLatLng: LatLng? { location.location.map { LatLng($0.coordinate) } }
    var selectedRoute: Route? { routeIndex < routes.count ? routes[routeIndex] : nil }

    // MARK: Search

    func queryChanged(_ q: String) {
        vlog.info("queryChanged \(q.count) chars")
        suggestTask?.cancel()
        guard let text = q.nonBlank, text.count >= 2 else { suggestions = SuggestResult(places: [], queries: []); return }
        let near = userLatLng ?? mapCenter, span = mapSpanMeters
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                let s = try await GoogleMaps.suggest(text, near: near, spanMeters: span)
                vlog.info("suggest -> \(s.places.count) places \(s.queries.count) queries")
                if !Task.isCancelled { suggestions = s }
            } catch {
                vlog.error("suggest failed: \(error.localizedDescription)")
            }
        }
    }

    func submitSearch(_ q: String? = nil) {
        let text = (q ?? query).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        query = text
        searchFocused = false
        searching = true
        suggestions = SuggestResult(places: [], queries: [])
        let viewport = mapCenter, span = mapSpanMeters, user = userLatLng
        Task {
            defer { searching = false }
            do {
                let r = try await GoogleMaps.search(text, viewport: viewport, spanMeters: span, user: user)
                results = r.places
                if r.places.count == 1 {
                    select(r.places[0])
                } else {
                    sheet = .results
                    // Frame the hits round the searched area only: one far-off or badly placed row
                    // otherwise zooms the map out to the whole world.
                    let reach = max(span * 2, 20_000)
                    let near = r.places.prefix(20).map(\.location).filter { $0.distance(to: viewport) <= reach }
                    if !near.isEmpty { camera = CameraRequest(kind: .fit(near)) }
                    else if let first = r.places.first { camera = CameraRequest(kind: .center(first.location, zoom: 14)) }
                    else { errorMessage = "No results for \u{201C}\(text)\u{201D}" }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pickSuggestion(_ p: Place) {
        searchFocused = false
        query = p.name
        suggestions = SuggestResult(places: [], queries: [])
        select(p)
        Task {
            let full = await GoogleMaps.details(p)
            if selected?.id == p.id { selected = full; remember(full) }
        }
    }

    func select(_ p: Place) {
        selected = p
        sheet = .place
        camera = CameraRequest(kind: .center(p.location, zoom: 16))
        remember(p)
    }

    func dropPin(_ at: LatLng) {
        guard nav == nil, sheet != .directions else { return }
        let pin = Place(id: "pin", name: "Dropped pin", location: at)
        selected = pin
        sheet = .place
        Task {
            let named = await Nominatim.reverse(at)
            if selected?.id == "pin" { selected = named }
        }
    }

    func clearSearch() {
        query = ""
        results = []
        selected = nil
        suggestions = SuggestResult(places: [], queries: [])
        sheet = .none
    }

    private func remember(_ p: Place) {
        guard p.id != "pin" else { return }
        recents.removeAll { $0.id == p.id }
        recents.insert(p, at: 0)
        if recents.count > 20 { recents.removeLast(recents.count - 20) }
    }

    // MARK: Saved

    /// Every place in any list, newest list entries first, each once.
    var saved: [Place] {
        var seen = Set<String>()
        return lists.flatMap(\.places).filter { seen.insert($0.id).inserted }
    }

    func isSaved(_ p: Place) -> Bool { lists.contains { $0.contains(p) } || shortcut(of: p) != nil }

    func isIn(_ p: Place, list id: String) -> Bool { lists.first { $0.id == id }?.contains(p) == true }

    func toggle(_ p: Place, list id: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        if lists[i].contains(p) { lists[i].places.removeAll { $0.id == p.id } } else { lists[i].places.insert(p, at: 0) }
    }

    @discardableResult
    func createList(_ name: String, with p: Place? = nil) -> String? {
        guard let name = name.nonBlank else { return nil }
        let list = SavedList(id: UUID().uuidString, name: name, icon: "list.bullet", places: p.map { [$0] } ?? [], builtIn: false)
        lists.append(list)
        return list.id
    }

    func deleteList(_ id: String) { lists.removeAll { $0.id == id && !$0.builtIn } }

    func shortcut(of p: Place) -> Shortcut? {
        if home?.id == p.id { return .home }
        if work?.id == p.id { return .work }
        return nil
    }

    func place(for s: Shortcut) -> Place? { s == .home ? home : work }

    func setShortcut(_ s: Shortcut, to p: Place?) {
        var labeled = p
        if let p, p.id == "pin" { labeled?.id = String(format: "pin:%.6f,%.6f", p.location.lat, p.location.lng) }
        if s == .home { home = labeled } else { work = labeled }
    }

    /// Home or Work tapped: directions there when set, else the Saved tab's picker to set it.
    func go(_ s: Shortcut) {
        searchFocused = false
        if let p = place(for: s) {
            directions(to: p)
        } else {
            pickingShortcut = s
            sheet = .saved
        }
    }

    // MARK: Directions

    static let needStart = "Choose a starting point"

    var locationAvailable: Bool { userLatLng != nil }
    var locationDenied: Bool { location.authorization == .denied || location.authorization == .restricted }

    func directions(to p: Place) {
        destination = p
        origin = nil
        routeNote = nil
        sheet = .directions
        fetchRoutes()
    }

    /// Sets the trip's start (`isOrigin`) or end. A nil start means "Your location".
    func setEndpoint(_ p: Place?, isOrigin: Bool) {
        if isOrigin { origin = p } else if let p { destination = p }
        fetchRoutes()
    }

    /// Start and end trade places; "Your location" travels as a place pinned to the current fix.
    func swapEndpoints() {
        guard let dest = destination else { return }
        let from: Place? = origin ?? userLatLng.map { Place(id: "me", name: "Your location", location: $0) }
        guard let from else { routeNote = Self.needStart; return }
        destination = from
        origin = dest
        fetchRoutes()
    }

    func fetchRoutes() {
        guard let dest = destination else { return }
        routes = []
        routeIndex = 0
        guard let from = origin?.location ?? userLatLng else {
            routeNote = Self.needStart
            return
        }
        routeNote = nil
        loadingRoutes = true
        let mode = mode, prefs = prefs
        Task {
            defer { loadingRoutes = false }
            do {
                let r = try await RouteService.routes(from: from, to: dest.location, mode: mode, prefs: prefs)
                guard self.mode == mode, destination?.id == dest.id else { return }
                routes = r
                if let first = r.first { camera = CameraRequest(kind: .fit(first.polyline)) }
                if r.isEmpty { routeNote = "No route found" }
            } catch {
                guard self.mode == mode, destination?.id == dest.id else { return }
                routeNote = "Couldn't get directions. Check your connection."
            }
        }
    }

    func closeDirections() {
        routes = []
        destination = nil
        origin = nil
        routeNote = nil
        sheet = selected == nil ? (results.isEmpty ? .none : .results) : .place
    }

    // MARK: Navigation

    func startNavigation() {
        guard let route = selectedRoute, let dest = destination else { return }
        #if DEBUG
        // The simulator drives this file: xcrun simctl location booted start --speed=22 $(cat last-route.txt)
        let dump = route.polyline.map { String(format: "%.6f,%.6f", $0.lat, $0.lng) }.joined(separator: " ")
        try? dump.write(to: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("last-route.txt"), atomically: true, encoding: .utf8)
        #endif
        let session = NavSession(route: route, destination: dest, prefs: prefs)
        session.onEnd = { [weak self] in self?.stopNavigation() }
        nav = session
        sheet = .navigating
        UIApplication.shared.isIdleTimerDisabled = true
        location.setNavigating(true, mode: route.mode)
        session.start()
        camera = CameraRequest(kind: .follow)
    }

    func stopNavigation() {
        nav?.stop()
        nav = nil
        UIApplication.shared.isIdleTimerDisabled = false
        location.setNavigating(false)
        sheet = .directions
        if let r = selectedRoute { camera = CameraRequest(kind: .fit(r.polyline)) }
    }
}

enum Shortcut: String, Codable, CaseIterable, Identifiable {
    case home, work
    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Work" }
    var symbol: String { self == .home ? "house.fill" : "briefcase.fill" }
}

struct SavedList: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String
    var places: [Place]
    var builtIn: Bool

    func contains(_ p: Place) -> Bool { places.contains { $0.id == p.id } }

    static let defaults = [
        SavedList(id: "favorites", name: "Favorites", icon: "heart.fill", places: [], builtIn: true),
        SavedList(id: "want-to-go", name: "Want to go", icon: "flag.fill", places: [], builtIn: true),
        SavedList(id: "starred", name: "Starred places", icon: "star.fill", places: [], builtIn: true),
    ]

    /// The stored lists; on first run, the defaults with the old flat saved places in Favorites.
    static func loadAll() -> [SavedList] {
        if let stored: [SavedList] = Store.load("saved_lists") { return stored }
        var lists = defaults
        lists[0].places = Store.load("saved_places") ?? []
        return lists
    }
}

enum Store {
    static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
}
