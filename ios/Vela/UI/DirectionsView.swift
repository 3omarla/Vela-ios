import SwiftUI

struct DirectionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSteps = false
    /// Which end of the trip is being picked: true = start, false = destination, nil = none.
    @State private var editing: Bool?

    var body: some View {
        if let isOrigin = editing {
            EndpointPicker(isOrigin: isOrigin) { editing = nil }
        } else {
            routesPanel
        }
    }

    private var originLabel: String {
        if let o = model.origin { return o.name }
        return model.locationAvailable ? "Your location" : "Choose starting point"
    }

    private var routesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 6) {
                    Circle().stroke(GM.blue, lineWidth: 2.5).frame(width: 10, height: 10)
                    ForEach(0..<3) { _ in Circle().fill(GM.muted).frame(width: 2.5, height: 2.5) }
                    Image(systemName: "mappin").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(light: 0xEA4335, dark: 0xF28B82))
                }
                VStack(spacing: 8) {
                    Button { editing = true } label: {
                        field(originLabel, placeholder: model.origin == nil && !model.locationAvailable)
                    }
                    .buttonStyle(.plain)
                    Button { editing = false } label: { field(model.destination?.name ?? "Choose destination", placeholder: model.destination == nil) }
                        .buttonStyle(.plain)
                }
                VStack(spacing: 8) {
                    Button { model.closeDirections() } label: { CircleIcon(symbol: "xmark") }
                    Button { model.swapEndpoints() } label: { CircleIcon(symbol: "arrow.up.arrow.down") }
                }
            }

            HStack(spacing: 8) {
                ForEach(TravelMode.allCases) { m in
                    let on = model.mode == m
                    Button { model.mode = m } label: {
                        HStack(spacing: 6) {
                            Image(systemName: m.symbol)
                            if on, let r = model.selectedRoute, !model.loadingRoutes { Text(Units.duration(r.bestDuration)) }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14).frame(height: 34)
                        .foregroundStyle(on ? GM.onTonal : GM.muted)
                        .background(on ? GM.tonal : .clear, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : GM.outline))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Menu {
                    Toggle("Avoid tolls", isOn: $model.prefs.avoidTolls)
                    Toggle("Avoid highways", isOn: $model.prefs.avoidHighways)
                    Toggle("Avoid ferries", isOn: $model.prefs.avoidFerries)
                } label: { CircleIcon(symbol: "slider.horizontal.3") }
                .onChange(of: model.prefs) { _, _ in model.fetchRoutes() }
            }
            .onChange(of: model.mode) { _, _ in model.fetchRoutes() }

            if model.loadingRoutes {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 24)
            } else if model.routes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.routeNote ?? "No routes yet").font(.system(size: 15)).foregroundStyle(GM.muted)
                    if model.routeNote == AppModel.needStart {
                        if model.locationDenied {
                            Text("Location is off for Vela. Pick a start, or turn location on in Settings.")
                                .font(.system(size: 13)).foregroundStyle(GM.muted)
                        }
                        Button { editing = true } label: { Label("Choose starting point", systemImage: "mappin.and.ellipse") }
                            .buttonStyle(FilledPill())
                    } else if model.routeNote != nil {
                        Button { model.fetchRoutes() } label: { Label("Try again", systemImage: "arrow.clockwise") }
                            .buttonStyle(TonalPill())
                    }
                }
                .padding(.vertical, 8)
            } else if showSteps, let r = model.selectedRoute {
                StepsList(route: r)
                Button { showSteps = false } label: { Label("Routes", systemImage: "chevron.backward") }.buttonStyle(TonalPill())
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.routes.enumerated()), id: \.element.id) { i, r in
                            RouteCard(route: r, selected: i == model.routeIndex, fastest: r.bestDuration <= model.routes.map(\.bestDuration).min()!)
                                .onTapGesture {
                                    model.routeIndex = i
                                    model.camera = CameraRequest(kind: .fit(r.polyline))
                                }
                            Divider()
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { model.startNavigation() } label: {
                        Label("Start", systemImage: "location.north.fill")
                    }
                    .buttonStyle(FilledPill())
                    Button { showSteps = true } label: { Label("Steps", systemImage: "list.bullet") }
                        .buttonStyle(TonalPill())
                    Spacer()
                }
            }
        }
        .padding(20)
    }

    private func field(_ text: String, placeholder: Bool = false) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(placeholder ? GM.blue : GM.onSurface).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).stroke(GM.outline))
    }
}

/// Picks one end of the trip: your location, a saved or recent place, or a Google autocomplete hit.
struct EndpointPicker: View {
    @EnvironmentObject var model: AppModel
    let isOrigin: Bool
    let done: () -> Void
    /// Set when the picker chooses something other than a trip end (Home, Work).
    var prompt: String?
    var onPick: ((Place) -> Void)?
    @State private var text = ""
    @State private var found = SuggestResult(places: [], queries: [])
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { done() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium)).foregroundStyle(GM.muted)
                }
                TextField(prompt ?? (isOrigin ? "Choose starting point" : "Choose destination"), text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, q in lookUp(q) }
                    .onSubmit { if let first = found.places.first { pick(first) } }
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark").foregroundStyle(GM.muted) }
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(GM.surfaceHigh, in: Capsule())
            .padding(20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if text.isEmpty {
                        if onPick == nil {
                            ForEach(Shortcut.allCases) { sc in
                                if let p = model.place(for: sc) { row(sc.symbol, sc.title, p.address, tint: GM.blue) { pick(p) } }
                            }
                        }
                        if onPick != nil {
                            EmptyView()
                        } else if model.locationAvailable {
                            row("location.fill", "Your location", nil, tint: GM.blue) { pick(nil) }
                        } else {
                            row("location.slash", "Your location", model.locationDenied ? "Location is off for Vela" : "Waiting for a location fix",
                                tint: GM.muted) {}
                                .opacity(0.6)
                        }
                        ForEach(model.saved) { p in row("bookmark.fill", p.name, p.address) { pick(p) } }
                        ForEach(model.recents.prefix(10)) { p in row("clock", p.name, p.address) { pick(p) } }
                    }
                    ForEach(found.places) { p in row("mappin.and.ellipse", p.name, p.address) { pick(p) } }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focused = true }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String?, tint: Color = GM.muted, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint)
                    .frame(width: 36, height: 36).background(GM.surfaceHigh, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16)).foregroundStyle(GM.onSurface).lineLimit(1)
                    if let subtitle { Text(Bidi.ltr(subtitle)).font(.system(size: 14)).foregroundStyle(GM.muted).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lookUp(_ q: String) {
        task?.cancel()
        guard let t = q.nonBlank, t.count >= 2 else { found = SuggestResult(places: [], queries: []); return }
        let near = model.userLatLng ?? model.destination?.location ?? model.mapCenter
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let r = try? await GoogleMaps.suggest(t, near: near, spanMeters: 50_000), !Task.isCancelled else { return }
            found = r
        }
    }

    private func pick(_ p: Place?) {
        if let onPick { if let p { onPick(p) }; done(); return }
        model.setEndpoint(p, isOrigin: isOrigin)
        done()
    }
}

struct RouteCard: View {
    let route: Route
    let selected: Bool
    let fastest: Bool

    private var trafficColor: Color {
        let ratio = route.trafficDelay / max(route.durationSeconds, 1)
        return ratio > 0.25 ? GM.closed : ratio > 0.1 ? Color(light: 0xB06000, dark: 0xFCC934) : GM.open
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.duration(route.bestDuration)).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(route.mode == .drive && route.durationInTrafficSeconds != nil ? trafficColor : GM.onSurface)
                    Text("(\(Units.distance(route.distanceMeters)))").foregroundStyle(GM.muted)
                }
                if let s = route.summary { Text("via \(s)").font(.subheadline).lineLimit(1) }
                if route.mode == .drive, route.trafficDelay >= 60 {
                    Text("\(Units.duration(route.trafficDelay)) delay from traffic").font(.caption).foregroundStyle(trafficColor)
                } else if fastest {
                    Text("Fastest route").font(.caption).foregroundStyle(.secondary)
                }
                if let lo = route.typicalLowSeconds, let hi = route.typicalHighSeconds {
                    Text("Typically \(Units.duration(lo)) to \(Units.duration(hi))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Arrive \(Units.arrival(after: route.bestDuration))").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12).padding(.leading, 12)
        .overlay(alignment: .leading) { Capsule().fill(selected ? GM.blue : .clear).frame(width: 4) }
        .contentShape(Rectangle())
    }
}

struct StepsList: View {
    let route: Route

    var body: some View {
        List(Array(route.maneuvers.enumerated()), id: \.offset) { _, m in
            HStack(spacing: 14) {
                Image(systemName: m.type.symbol).font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.instruction)
                    if let l = m.laneHint { Text(l).font(.caption).foregroundStyle(.secondary) }
                    if m.distanceMeters > 0 && m.type != .arrive {
                        Text(Units.distance(m.distanceMeters)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
