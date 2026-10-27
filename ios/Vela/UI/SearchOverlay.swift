import SwiftUI

struct SearchOverlay: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if model.searchFocused {
                    Button { focused = false } label: {
                        Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium)).foregroundStyle(GM.muted)
                    }
                } else {
                    VelaMark()
                }
                TextField("Search here", text: $model.query)
                    .font(.system(size: 17))
                    .foregroundStyle(GM.onSurface)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { model.submitSearch() }
                    .onChange(of: model.query) { _, q in if model.searchFocused { model.queryChanged(q) } }
                if model.searching { ProgressView().controlSize(.small) }
                if !model.query.isEmpty {
                    Button { model.clearSearch(); focused = true } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).foregroundStyle(GM.muted)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(model.searchFocused ? GM.surfaceHigh : GM.surface, in: Capsule())
            // The whole pill takes the tap, not only the text field's own line box.
            .contentShape(Capsule())
            .onTapGesture { focused = true }
            .modifier(GM.elevation(model.searchFocused ? 0 : 2))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if model.searchFocused {
                SuggestionsList(dismiss: { focused = false })
                    .padding(.top, 10)
            } else if model.sheet == .none {
                QuickChips()
            }
            Spacer(minLength: 0)
            if !model.searchFocused { MapButtons() }
        }
        .background(model.searchFocused ? GM.surface.ignoresSafeArea() : nil)
        .onChange(of: focused) { _, f in model.searchFocused = f }
    }
}

struct QuickChips: View {
    @EnvironmentObject var model: AppModel
    private let chips: [(String, String, Color)] = [
        ("Restaurants", "fork.knife", Color(light: 0xE8710A, dark: 0xF6AE6C)),
        ("Gas", "fuelpump.fill", Color(light: 0x1A73E8, dark: 0x8AB4F8)),
        ("Coffee", "cup.and.saucer.fill", Color(light: 0x8D6E63, dark: 0xBCAAA4)),
        ("Groceries", "cart.fill", Color(light: 0x1A73E8, dark: 0x8AB4F8)),
        ("Hotels", "bed.double.fill", Color(light: 0xD01884, dark: 0xF48FB1)),
        ("Parking", "parkingsign", Color(light: 0x1A73E8, dark: 0x8AB4F8)),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.0) { c in
                    Button { model.submitSearch(c.0) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.1).foregroundStyle(c.2)
                            Text(c.0).foregroundStyle(GM.onSurface)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(GM.surface, in: Capsule())
                        .modifier(GM.elevation(1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.top, 4)
    }
}

/// Saved places, recents and the autocomplete answer, in plain rows: a List cell's selection
/// handling dropped taps while the keyboard was moving or the rows were replaced.
struct SuggestionsList: View {
    @EnvironmentObject var model: AppModel
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.query.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Shortcut.allCases) { sc in
                            Button { dismiss(); model.go(sc) } label: {
                                Label(model.place(for: sc) == nil ? "Set \(sc.title.lowercased())" : sc.title, systemImage: sc.symbol)
                            }
                            .buttonStyle(TonalPill())
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                    if !model.saved.isEmpty {
                        header("Saved")
                        ForEach(model.saved) { p in row(p, icon: "bookmark.fill") }
                    }
                    if !model.recents.isEmpty {
                        header("Recent")
                        ForEach(model.recents.prefix(10)) { p in row(p, icon: "clock") }
                    }
                }
                ForEach(model.suggestions.queries, id: \.self) { q in
                    Button { dismiss(); model.submitSearch(q) } label: {
                        rowBody(icon: "magnifyingglass", title: q, subtitle: nil, trailing: nil)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(model.suggestions.places) { p in row(p, icon: "mappin.and.ellipse") }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .medium)).foregroundStyle(GM.muted)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
    }

    private func row(_ p: Place, icon: String) -> some View {
        Button { dismiss(); model.pickSuggestion(p) } label: {
            rowBody(icon: icon, title: p.name, subtitle: p.address,
                    trailing: model.userLatLng.map { Units.distance($0.distance(to: p.location)) })
        }
        .buttonStyle(.plain)
    }

    private func rowBody(icon: String, title: String, subtitle: String?, trailing: String?) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(GM.muted)
                .frame(width: 36, height: 36).background(GM.surfaceHigh, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(GM.onSurface).lineLimit(1)
                if let subtitle { Text(Bidi.ltr(subtitle)).font(.system(size: 14)).foregroundStyle(GM.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.system(size: 13)).foregroundStyle(GM.muted) }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct MapButtons: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            Spacer()
            Button {
                if let u = model.userLatLng { model.camera = CameraRequest(kind: .center(u, zoom: 15)) }
            } label: {
                Image(systemName: "location.fill").font(.system(size: 20))
                    .foregroundStyle(GM.blue)
                    .frame(width: 56, height: 56)
                    .background(GM.surface, in: Circle())
                    .modifier(GM.elevation(2))
            }
            .padding(.trailing, 16)
            .padding(.bottom, model.sheet == .none ? 12 : 130)
        }
    }
}

/// Explore / Saved, along the bottom while the map is bare.
struct BottomBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            tab("Explore", "safari", selected: model.sheet == .none) { model.sheet = .none }
            tab("Saved", "bookmark", selected: model.sheet == .saved) { model.sheet = .saved }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(GM.surface.ignoresSafeArea(edges: .bottom))
        .modifier(GM.elevation(1))
    }

    private func tab(_ title: String, _ symbol: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: selected ? symbol + ".fill" : symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 56, height: 30)
                    .background(selected ? GM.tonal : .clear, in: Capsule())
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? GM.onTonal : GM.muted)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// The Saved tab: Home and Work, then the lists; a list opens to its places.
struct SavedView: View {
    @EnvironmentObject var model: AppModel
    @State private var openList: String?
    @State private var askNewList = false
    @State private var newListName = ""

    var body: some View {
        if let sc = model.pickingShortcut {
            EndpointPicker(isOrigin: false, done: { model.pickingShortcut = nil }, prompt: "Set \(sc.title.lowercased()) address") { p in
                model.setShortcut(sc, to: p)
            }
        } else if let id = openList, let list = model.lists.first(where: { $0.id == id }) {
            listDetail(list)
        } else {
            overview
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Saved").font(.system(size: 24)).foregroundStyle(GM.onSurface).padding(20)
                HStack(spacing: 10) {
                    ForEach(Shortcut.allCases) { sc in shortcutTile(sc) }
                }
                .padding(.horizontal, 20)
                HStack {
                    Text("Your lists").font(.system(size: 14, weight: .medium)).foregroundStyle(GM.muted)
                    Spacer()
                    Button { newListName = ""; askNewList = true } label: { Label("New list", systemImage: "plus") }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(GM.blue)
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 6)
                ForEach(model.lists) { l in
                    Button { openList = l.id } label: {
                        HStack(spacing: 16) {
                            Image(systemName: l.icon).foregroundStyle(GM.blue)
                                .frame(width: 40, height: 40).background(GM.tonal.opacity(0.5), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(.system(size: 16)).foregroundStyle(GM.onSurface)
                                Text(l.places.count == 1 ? "1 place" : "\(l.places.count) places").font(.system(size: 13)).foregroundStyle(GM.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(GM.muted)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !l.builtIn { Button(role: .destructive) { model.deleteList(l.id) } label: { Label("Delete list", systemImage: "trash") } }
                    }
                }
            }
        }
        .alert("New list", isPresented: $askNewList) {
            TextField("List name", text: $newListName)
            Button("Create") { model.createList(newListName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shortcutTile(_ sc: Shortcut) -> some View {
        let p = model.place(for: sc)
        return Button { if let p { model.select(p) } else { model.pickingShortcut = sc } } label: {
            HStack(spacing: 12) {
                Image(systemName: sc.symbol).foregroundStyle(GM.blue)
                    .frame(width: 36, height: 36).background(GM.tonal.opacity(0.5), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(sc.title).font(.system(size: 15, weight: .medium)).foregroundStyle(GM.onSurface)
                    Text(p.map { Bidi.ltr($0.address ?? $0.name) } ?? "Set location").font(.system(size: 12))
                        .foregroundStyle(p == nil ? GM.blue : GM.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).stroke(GM.outline))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { model.pickingShortcut = sc } label: { Label("Change", systemImage: "pencil") }
            if p != nil { Button(role: .destructive) { model.setShortcut(sc, to: nil) } label: { Label("Remove", systemImage: "trash") } }
        }
    }

    private func listDetail(_ l: SavedList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { openList = nil } label: { CircleIcon(symbol: "chevron.left") }
                    Text(l.name).font(.system(size: 22)).foregroundStyle(GM.onSurface)
                    Spacer()
                }
                .padding(20)
                if l.places.isEmpty {
                    Text("No places yet. Use Save on a place to add it.").foregroundStyle(GM.muted).padding(.horizontal, 20)
                }
                ForEach(l.places) { p in
                    Button { model.select(p) } label: { PlaceRow(place: p).padding(.horizontal, 20) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { model.toggle(p, list: l.id) } label: { Label("Remove from list", systemImage: "trash") }
                        }
                    Divider().padding(.leading, 20)
                }
            }
        }
    }
}
