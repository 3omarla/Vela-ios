import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var detent: PresentationDetent = .fraction(0.4)

    private var sheetShown: Binding<Bool> {
        Binding(get: { model.sheet != .none && model.sheet != .navigating && !model.searchFocused },
                set: { if !$0 { dismissSheet() } })
    }

    var body: some View {
        ZStack(alignment: .top) {
            VelaMapView(model: model, dark: scheme == .dark)
                .ignoresSafeArea()

            if let nav = model.nav {
                NavigationOverlay(session: nav)
            } else if model.sheet != .directions {
                SearchOverlay()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.nav == nil && !model.searchFocused && (model.sheet == .none || model.sheet == .saved) { BottomBar() }
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
