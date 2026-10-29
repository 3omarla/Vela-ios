import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.verticalSizeClass) private var vSize
    @State private var detent: PresentationDetent = .fraction(0.4)

    /// Width of the left column that holds search, the panels and the drive banner in landscape.
    static let panelWidth: CGFloat = 380

    /// A phone on its side: the bottom sheet becomes a side panel.
    private var landscape: Bool { vSize == .compact }

    private var sheetWanted: Bool { model.sheet != .none && model.sheet != .navigating && !model.searchFocused }

    private var sheetShown: Binding<Bool> {
        // A rotation hides the sheet; only a swipe in portrait closes what it shows.
        Binding(get: { sheetWanted && !landscape },
                set: { if !$0 && !landscape && sheetWanted { dismissSheet() } })
    }

    /// The map's left edge under the side column, so the camera frames the open part.
    private var sideInset: CGFloat {
        guard landscape else { return 0 }
        if model.nav != nil || sheetWanted { return Self.panelWidth + 16 }
        return 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            VelaMapView(model: model, dark: scheme == .dark, sidePanel: sideInset)
                .ignoresSafeArea()

            if let nav = model.nav {
                NavigationOverlay(session: nav, landscape: landscape)
            } else if landscape {
                LandscapeChrome()
            } else if model.sheet != .directions {
                SearchOverlay()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !landscape && model.nav == nil && !model.searchFocused && (model.sheet == .none || model.sheet == .saved) { BottomBar() }
        }
        .sheet(isPresented: sheetShown) {
            SheetContent()
                .presentationDetents([.height(120), .fraction(0.4), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
                .presentationDragIndicator(.visible)
                .presentationBackground(GM.surface)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled(model.sheet == .directions)
        }
        .onChange(of: model.sheet) { _, s in
            if s == .place || s == .results || s == .directions { detent = .fraction(0.4) }
        }
        .overlay(alignment: .top) {
            if let msg = model.errorMessage {
                Text(msg)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(light: 0xF2F2F2, dark: 0x1F1F1F))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(light: 0x303030, dark: 0xE3E3E3), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 70).padding(.horizontal, 16)
                    .onTapGesture { model.errorMessage = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
    }

    private func dismissSheet() {
        switch model.sheet {
        case .place:
            model.selected = nil
            model.sheet = model.results.isEmpty ? .none : .results
        case .results: model.clearSearch()
        case .saved: model.sheet = .none
        default: break
        }
    }
}

/// Landscape browsing: search and the open panel in a left column, the map buttons on the right.
struct LandscapeChrome: View {
    @EnvironmentObject var model: AppModel

    private var panelOpen: Bool {
        !model.searchFocused && [.results, .place, .directions, .saved].contains(model.sheet)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                if model.sheet != .directions { SearchOverlay(landscape: true) }
                if panelOpen {
                    SheetContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .topTrailing) {
                            // Saved has no close of its own; in portrait it is swiped away.
                            if model.sheet == .saved {
                                Button { model.sheet = .none } label: { CircleIcon(symbol: "xmark") }.padding(16)
                            }
                        }
                        .background(GM.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .modifier(GM.elevation(2))
                        .padding(.horizontal, model.sheet == .directions ? 8 : 16)
                }
            }
            .frame(width: RootView.panelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(model.searchFocused ? GM.surface.clipShape(RoundedRectangle(cornerRadius: 24)) : nil)
            .padding(.vertical, 8)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Spacer()
                round(model.sheet == .saved ? "bookmark.fill" : "bookmark") {
                    model.sheet = model.sheet == .saved ? .none : .saved
                }
                round("location.fill") {
                    if let u = model.userLatLng { model.camera = CameraRequest(kind: .center(u, zoom: 15)) }
                }
            }
            .padding(.trailing, 16).padding(.bottom, 12)
        }
    }

    private func round(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19))
                .foregroundStyle(GM.blue)
                .frame(width: 52, height: 52)
                .background(GM.surface, in: Circle())
                .modifier(GM.elevation(2))
        }
    }
}

struct SheetContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.sheet {
        case .results: ResultsView()
        case .place:
            if let p = model.selected { PlaceView(place: p) }
        case .directions: DirectionsView()
        case .saved: SavedView()
        default: EmptyView()
        }
    }
}
