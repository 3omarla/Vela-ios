import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.query).font(.system(size: 22)).foregroundStyle(GM.onSurface).lineLimit(1)
                Spacer()
                Button { model.clearSearch() } label: { CircleIcon(symbol: "xmark") }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.results) { p in
                        Button { model.select(p) } label: { PlaceRow(place: p).padding(.horizontal, 20) }
                            .buttonStyle(.plain)
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }
}

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(.system(size: 17, weight: .medium)).foregroundStyle(GM.onSurface)
                RatingLine(place: place)
                SubtitleLine(place: place)
                StatusLine(place: place)
                if let f = place.fuelPrice { Text(f).font(.system(size: 14)).foregroundStyle(GM.open) }
            }
            Spacer()
            if let u = place.photoUrls.first, let url = URL(string: u) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { GM.surfaceHigh }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct RatingLine: View {
    let place: Place

    var body: some View {
        if let r = place.rating {
            HStack(spacing: 4) {
                Text(String(format: "%.1f", r)).foregroundStyle(GM.onSurface)
                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Image(systemName: Double(i) + 0.75 <= r ? "star.fill" : Double(i) + 0.25 <= r ? "star.leadinghalf.filled" : "star")
                            .font(.system(size: 11)).foregroundStyle(GM.star)
                    }
                }
                if let n = place.reviewCount { Text("(\(n.formatted()))").foregroundStyle(GM.muted) }
            }
            .font(.system(size: 14))
        }
    }
}

/// "Steak house · $$ · 2.1 km", the way the app joins the place's kind, price and distance.
struct SubtitleLine: View {
    let place: Place

    var body: some View {
        let parts = [place.category, place.priceText, place.distanceMeters.map(Units.distance)].compactMap { $0 }
        if !parts.isEmpty {
            Text(Bidi.join(parts)).font(.system(size: 14)).foregroundStyle(GM.muted).lineLimit(1)
        }
    }
}

/// "Open · Closes 12 AM": the state word in color, the rest muted.
struct StatusLine: View {
    let place: Place

    var body: some View {
        if place.permanentlyClosed {
            Text("Permanently closed").font(.system(size: 14, weight: .medium)).foregroundStyle(GM.closed)
        } else if place.temporarilyClosed {
            Text("Temporarily closed").font(.system(size: 14, weight: .medium)).foregroundStyle(GM.closed)
        } else if let s = place.statusText {
            let parts = s.components(separatedBy: " · ")
            let color = place.openNow == true ? GM.open : place.openNow == false ? GM.closed : GM.muted
            (Text(parts[0]).foregroundColor(color).fontWeight(.medium)
                + Text(parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : "").foregroundColor(GM.muted))
                .font(.system(size: 14))
        }
    }
}

struct PlaceView: View {
    @EnvironmentObject var model: AppModel
    let place: Place
    @State private var tab = 0
    @State private var showHours = false
    @State private var askNewList = false
    @State private var newListName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 20).padding(.top, 20)
                actions.padding(.top, 14)
                if !place.about.isEmpty {
                    tabs.padding(.top, 14)
                } else {
                    Divider().padding(.top, 14)
                }
                if tab == 0 { overview } else { about }
            }
        }
        .onChange(of: place.id) { _, _ in tab = 0 }
        .alert("New list", isPresented: $askNewList) {
            TextField("List name", text: $newListName)
            Button("Create") { model.createList(newListName, with: place) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.system(size: 24)).foregroundStyle(GM.onSurface)
                RatingLine(place: place)
                SubtitleLine(place: place)
                StatusLine(place: place)
            }
            Spacer()
            HStack(spacing: 8) {
                ShareLink(item: shareURL) { CircleIcon(symbol: "square.and.arrow.up") }
                Button { close() } label: { CircleIcon(symbol: "xmark") }
            }
        }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { model.directions(to: place) } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(FilledPill())
                if let phone = place.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) { Label("Call", systemImage: "phone") }.buttonStyle(TonalPill())
                }
                Menu {
                    ForEach(model.lists) { l in
                        Button { model.toggle(place, list: l.id) } label: {
                            Label(l.name, systemImage: model.isIn(place, list: l.id) ? "checkmark" : l.icon)
                        }
                    }
                    Button { newListName = ""; askNewList = true } label: { Label("New list", systemImage: "plus") }
                    Divider()
                    ForEach(Shortcut.allCases) { sc in
                        let isIt = model.shortcut(of: place) == sc
                        Button { model.setShortcut(sc, to: isIt ? nil : place) } label: {
                            Label(isIt ? "Remove as \(sc.title)" : "Set as \(sc.title)", systemImage: sc.symbol)
                        }
                    }
                } label: {
                    Label(model.isSaved(place) ? "Saved" : "Save", systemImage: model.isSaved(place) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(TonalPill())
                if let a = place.actionUrl, let url = URL(string: a) {
                    Link(destination: url) { Label(place.actionLabel ?? "Book", systemImage: "calendar") }.buttonStyle(TonalPill())
                }
                if let w = place.website, let url = URL(string: w) {
                    Link(destination: url) { Label("Website", systemImage: "globe") }.buttonStyle(TonalPill())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Overview", "About"].enumerated()), id: \.offset) { i, t in
                    Button { withAnimation(.easeOut(duration: 0.15)) { tab = i } } label: {
                        VStack(spacing: 8) {
                            Text(t).font(.system(size: 15, weight: .medium))
                                .foregroundStyle(tab == i ? GM.blue : GM.muted)
                            Capsule().fill(tab == i ? GM.blue : .clear).frame(width: 64, height: 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !place.photoUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(place.photoUrls.enumerated()), id: \.offset) { i, u in
                            AsyncImage(url: URL(string: u)) { $0.resizable().scaledToFill() } placeholder: { GM.surfaceHigh }
                                .frame(width: i == 0 ? 240 : 150, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            if let s = place.editorialSummary {
                Text(s).font(.system(size: 15)).foregroundStyle(GM.muted).padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            if let a = place.address { InfoRow(icon: "mappin.and.ellipse", text: a) }
            if !place.hours.isEmpty {
                Button { withAnimation { showHours.toggle() } } label: {
                    HStack(alignment: .top, spacing: 20) {
                        Image(systemName: "clock").foregroundStyle(GM.blue).frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                StatusLine(place: place)
                                Spacer()
                                Image(systemName: showHours ? "chevron.up" : "chevron.down").foregroundStyle(GM.muted)
                            }
                            if showHours {
                                ForEach(place.hours, id: \.self) { h in
                                    Text(h).font(.system(size: 14)).foregroundStyle(GM.onSurface)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
            }
            ForEach(place.departments, id: \.name) { d in
                InfoRow(icon: "building.2", text: "\(d.name): \(d.statusText ?? d.hours.first ?? "")")
            }
            if let w = place.website { InfoRow(icon: "globe", text: URL(string: w)?.host ?? w) }
            if let phone = place.phone { InfoRow(icon: "phone", text: phone) }
            InfoRow(icon: "location.viewfinder", text: String(format: "%.5f, %.5f", place.location.lat, place.location.lng))
            if let r = place.featuredReview {
                Text("\u{201C}\(r)\u{201D}").font(.system(size: 15)).italic().foregroundStyle(GM.muted).padding(20)
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let s = place.editorialSummary { Text(s).font(.system(size: 15)).foregroundStyle(GM.onSurface) }
            ForEach(place.about, id: \.title) { s in
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.title).font(.system(size: 16, weight: .medium)).foregroundStyle(GM.onSurface)
                    ForEach(s.items, id: \.self) { item in
                        Label(item, systemImage: "checkmark").font(.system(size: 14)).foregroundStyle(GM.muted)
                    }
                }
            }
        }
        .padding(20)
    }

    private var shareURL: URL {
        if let pid = place.placeId {
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(place.name.urlEncoded)&query_place_id=\(pid)")!
        }
        return URL(string: "https://www.openstreetmap.org/?mlat=\(place.location.lat)&mlon=\(place.location.lng)#map=17/\(place.location.lat)/\(place.location.lng)")!
    }

    private func close() {
        model.selected = nil
        model.sheet = model.results.isEmpty ? .none : .results
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: icon).foregroundStyle(GM.blue).frame(width: 24)
                Text(Bidi.ltr(text)).font(.system(size: 15)).foregroundStyle(GM.onSurface).textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().padding(.leading, 64)
        }
    }
}
