import SwiftUI

struct NavigationOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: NavSession
    var landscape = false

    var body: some View {
        if landscape {
            // Banner and trip bar in the left column; the arrow drives through the open map.
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 10) {
                    maneuverBanner
                    Spacer(minLength: 0)
                    bottomBar.clipShape(RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 10)
                }
                .frame(width: RootView.panelWidth)
                .padding(.vertical, 8)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer()
                    recenter
                    SpeedBadge(mps: session.speedMps)
                }
                .padding(.trailing, 16).padding(.bottom, 12)
            }
        } else {
            VStack(spacing: 0) {
                maneuverBanner
                Spacer()
                HStack {
                    SpeedBadge(mps: session.speedMps)
                    Spacer()
                    recenter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                bottomBar
            }
        }
    }

    private var recenter: some View {
        Button { model.camera = CameraRequest(kind: .follow) } label: {
            Label("Re-center", systemImage: "location.north.line.fill")
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private var maneuverBanner: some View {
        let e = session.engine
        return VStack(alignment: .leading, spacing: 6) {
            if session.rerouting {
                HStack { ProgressView().tint(.white); Text("Rerouting").font(.title3.bold()) }
            } else if session.arrived {
                HStack { Image(systemName: "flag.checkered").font(.largeTitle); Text("You've arrived").font(.title2.bold()) }
            } else if let m = e.currentManeuver {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: m.type.symbol).font(.system(size: 44, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Units.distance(e.distanceToManeuver)).font(.title.bold())
                        Text(m.road ?? m.instruction).font(.title3).lineLimit(2)
                    }
                }
                if let lane = m.laneHint { Text(lane).font(.subheadline).opacity(0.9) }
                if let n = e.nextManeuver, n.alongMeters - m.alongMeters < 300, n.type != .arrive {
                    HStack { Text("Then"); Image(systemName: n.type.symbol) }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.2), in: Capsule())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.06, green: 0.43, blue: 0.29)))
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        let e = session.engine
        return HStack {
            Button { session.muted.toggle() } label: {
                Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title3)
                    .frame(width: 48, height: 48).background(Color.secondary.opacity(0.15), in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(Units.duration(e.remainingSeconds)).font(.title2.bold()).foregroundStyle(.green)
                Text("\(Units.distance(e.remainingMeters)) · \(session.eta)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) { model.stopNavigation() } label: {
                Text("Exit").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.red, in: Capsule()).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

struct SpeedBadge: View {
    let mps: Double

    var body: some View {
        let v = Units.metric ? mps * 3.6 : mps * 2.23694
        VStack(spacing: 0) {
            Text("\(Int(v.rounded()))").font(.title2.bold())
            Text(Units.metric ? "km/h" : "mph").font(.caption2)
        }
        .frame(width: 64, height: 64)
        .background(.regularMaterial, in: Circle())
    }
}
