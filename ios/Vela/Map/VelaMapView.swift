import SwiftUI
import MapLibre

/// MapLibre map with Vela's layers: search results, the selected place, routes with live traffic.
struct VelaMapView: UIViewRepresentable {
    @ObservedObject var model: AppModel
    var dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.compassViewPosition = .topRight
        map.compassViewMargins = CGPoint(x: 16, y: 120)
        map.setCenter(model.mapCenter.coordinate, zoomLevel: 11, animated: false)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        map.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        map.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.forEach { tap.require(toFail: $0) }
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        context.coordinator.loadStyle(dark: dark)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        if c.dark != dark { c.loadStyle(dark: dark) }
        c.sync()
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        let model: AppModel
        weak var map: MLNMapView?
        var dark: Bool?
        private var lastCamera: UUID?
        private var styleReady = false
        private var lastSignature = ""
        private var following = false

        init(model: AppModel) { self.model = model }

        func loadStyle(dark: Bool) {
            self.dark = dark
            styleReady = false
            Task {
                let url = await MapStyle.load(dark: dark)
                map?.styleURL = url
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            lastSignature = ""
            installLayers(style)
            sync()
        }

        private func installLayers(_ style: MLNStyle) {
            let empty = MLNShapeCollectionFeature(shapes: [])
            for id in ["vela-routes", "vela-traffic", "vela-places", "vela-selected"] where style.source(withIdentifier: id) == nil {
                style.addSource(MLNShapeSource(identifier: id, shape: empty, options: nil))
            }
            let below = style.layers.first { ($0 as? MLNSymbolStyleLayer) != nil }
            func add(_ l: MLNStyleLayer) {
                if style.layer(withIdentifier: l.identifier) != nil { return }
                if let below { style.insertLayer(l, below: below) } else { style.addLayer(l) }
            }
            let routes = style.source(withIdentifier: "vela-routes")!
            let casing = MLNLineStyleLayer(identifier: "vela-route-casing", source: routes)
            casing.lineColor = NSExpression(format: "TERNARY(selected == 1, %@, %@)", UIColor(hex: "#1967d2"), UIColor(hex: "#7c9cc7"))
            casing.lineWidth = NSExpression(format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)", [10: 6, 18: 18])
            casing.lineCap = NSExpression(forConstantValue: "round"); casing.lineJoin = NSExpression(forConstantValue: "round")
            add(casing)
            let fill = MLNLineStyleLayer(identifier: "vela-route", source: routes)
            fill.lineColor = NSExpression(format: "TERNARY(selected == 1, %@, %@)", UIColor(hex: "#4285f4"), UIColor(hex: "#bccfeb"))
            fill.lineWidth = NSExpression(format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)", [10: 4, 18: 13])
            fill.lineCap = NSExpression(forConstantValue: "round"); fill.lineJoin = NSExpression(forConstantValue: "round")
            add(fill)
            let traffic = MLNLineStyleLayer(identifier: "vela-traffic", source: style.source(withIdentifier: "vela-traffic")!)
            traffic.lineColor = NSExpression(format: "TERNARY(level >= 2, %@, %@)", UIColor(hex: "#e53935"), UIColor(hex: "#f9a825"))
            traffic.lineWidth = fill.lineWidth
            traffic.lineCap = NSExpression(forConstantValue: "round")
            add(traffic)

            let places = style.source(withIdentifier: "vela-places")!
            let dot = MLNCircleStyleLayer(identifier: "vela-place-dot", source: places)
            dot.circleColor = NSExpression(forConstantValue: UIColor(hex: "#ea4335"))
            dot.circleRadius = NSExpression(forConstantValue: 7)
            dot.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            dot.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(dot)
            let label = MLNSymbolStyleLayer(identifier: "vela-place-label", source: places)
            label.text = NSExpression(forKeyPath: "name")
            label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            label.textFontSize = NSExpression(forConstantValue: 12)
            label.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.2)))
            label.textAnchor = NSExpression(forConstantValue: "top")
            label.textColor = NSExpression(forConstantValue: UIColor(hex: "#c5221f"))
            label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            label.textHaloWidth = NSExpression(forConstantValue: 1.5)
            label.textOptional = NSExpression(forConstantValue: true)
            style.addLayer(label)

            let sel = MLNSymbolStyleLayer(identifier: "vela-selected-pin", source: style.source(withIdentifier: "vela-selected")!)
            style.setImage(Self.pinImage(), forName: "vela-pin")
            sel.iconImageName = NSExpression(forConstantValue: "vela-pin")
            sel.iconAnchor = NSExpression(forConstantValue: "bottom")
            sel.iconAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(sel)
        }

        /// The selected-place pin: a red teardrop with a dark core, tip on the coordinate.
        static func pinImage() -> UIImage {
            let size = CGSize(width: 30, height: 42)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let r: CGFloat = 13, cx = size.width / 2, cy: CGFloat = 15
                let p = UIBezierPath()
                p.move(to: CGPoint(x: cx, y: size.height - 1))
                p.addCurve(to: CGPoint(x: cx - r, y: cy), controlPoint1: CGPoint(x: cx - 4, y: 30), controlPoint2: CGPoint(x: cx - r, y: 24))
                p.addArc(withCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
                p.addCurve(to: CGPoint(x: cx, y: size.height - 1), controlPoint1: CGPoint(x: cx + r, y: 24), controlPoint2: CGPoint(x: cx + 4, y: 30))
                p.close()
                UIColor(hex: "#ea4335").setFill(); p.fill()
                UIColor(hex: "#b31412").setStroke(); p.lineWidth = 1; p.stroke()
                UIColor(hex: "#b31412").setFill()
                UIBezierPath(ovalIn: CGRect(x: cx - 4.5, y: cy - 4.5, width: 9, height: 9)).fill()
            }
        }

        func sync() {
            guard let map else { return }
            if let req = model.camera, req.id != lastCamera {
                lastCamera = req.id
                apply(req, map)
            }
            let navigating = model.nav != nil
            if following != navigating {
                following = navigating
                if navigating {
                    map.setUserTrackingMode(.followWithCourse, animated: true, completionHandler: nil)
                    map.setCamera(MLNMapCamera(lookingAtCenter: map.centerCoordinate, altitude: 600, pitch: 50, heading: map.direction), animated: true)
                } else {
                    map.setUserTrackingMode(.none, animated: false, completionHandler: nil)
                    let cam = map.camera; cam.pitch = 0; map.setCamera(cam, animated: true)
                }
            }
            guard styleReady, let style = map.style else { return }
            let routes = model.nav.map { [$0.route] } ?? model.routes
            let selIdx = model.nav == nil ? model.routeIndex : 0
            let sig = "\(routes.map(\.id))|\(selIdx)|\(model.results.map(\.id).prefix(30))|\(model.selected?.id ?? "")|\(model.sheet)|\(model.destination?.id ?? "")"
            guard sig != lastSignature else { return }
            lastSignature = sig

            var lines: [MLNPolylineFeature] = []
            var jams: [MLNPolylineFeature] = []
            for (i, r) in routes.enumerated() {
                var coords = r.polyline.map(\.coordinate)
                let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                f.attributes = ["selected": i == selIdx ? 1 : 0]
                lines.append(f)
                if i == selIdx {
                    let cum = Geo.cumulative(r.polyline)
                    for s in r.trafficSpans {
                        var pts = [Geo.point(along: r.polyline, cum: cum, meters: s.startMeters)]
                        for (k, m) in cum.enumerated() where m > s.startMeters && m < s.startMeters + s.lengthMeters { pts.append(r.polyline[k]) }
                        pts.append(Geo.point(along: r.polyline, cum: cum, meters: s.startMeters + s.lengthMeters))
                        var c = pts.map(\.coordinate)
                        let jf = MLNPolylineFeature(coordinates: &c, count: UInt(c.count))
                        jf.attributes = ["level": s.level]
                        jams.append(jf)
                    }
                }
            }
            (style.source(withIdentifier: "vela-routes") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: lines.sorted { ($0.attributes["selected"] as? Int ?? 0) < ($1.attributes["selected"] as? Int ?? 0) })
            (style.source(withIdentifier: "vela-traffic") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: jams)

            let showResults = model.sheet == .results || (model.sheet == .place && !model.results.isEmpty)
            let pts: [MLNPointFeature] = (showResults ? model.results : []).filter { $0.id != model.selected?.id }.map { p in
                let f = MLNPointFeature(); f.coordinate = p.location.coordinate; f.attributes = ["name": p.name, "id": p.id]; return f
            }
            (style.source(withIdentifier: "vela-places") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: pts)
            let pinPlace = model.sheet == .directions || model.sheet == .navigating ? model.destination : model.selected
            let pin: [MLNPointFeature] = pinPlace.map { p in let f = MLNPointFeature(); f.coordinate = p.location.coordinate; return [f] } ?? []
            (style.source(withIdentifier: "vela-selected") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: pin)
        }

        private func apply(_ req: CameraRequest, _ map: MLNMapView) {
            switch req.kind {
            case .center(let p, let zoom):
                map.setUserTrackingMode(.none, animated: false, completionHandler: nil)
                // The sheet covers the bottom ~40%: aim at the middle of what is left.
                map.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: map.bounds.height * 0.35, right: 0)
                map.setCenter(p.coordinate, zoomLevel: zoom ?? max(map.zoomLevel, 15), direction: 0, animated: true)
            case .fit(let pts):
                guard !pts.isEmpty else { return }
                map.setUserTrackingMode(.none, animated: false, completionHandler: nil)
                map.contentInset = .zero
                if pts.count == 1 { map.setCenter(pts[0].coordinate, zoomLevel: 15, animated: true); return }
                var coords = pts.map(\.coordinate)
                let pad = UIEdgeInsets(top: 140, left: 50, bottom: map.bounds.height * 0.45, right: 50)
                map.setVisibleCoordinates(&coords, count: UInt(coords.count), edgePadding: pad, animated: true)
            case .follow:
                map.contentInset = UIEdgeInsets(top: map.bounds.height * 0.35, left: 0, bottom: 0, right: 0)
                map.setUserTrackingMode(.followWithCourse, animated: true, completionHandler: nil)
            }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            model.mapCenter = LatLng(mapView.centerCoordinate)
            let b = mapView.visibleCoordinateBounds
            model.mapSpanMeters = Geo.distance(LatLng(b.sw), LatLng(b.ne.latitude, b.sw.longitude))
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            // A pan during a drive drops follow mode; the recenter button brings it back.
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map else { return }
            let c = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.dropPin(LatLng(c))
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let map, model.nav == nil else { return }
            let pt = g.location(in: map)
            let rect = CGRect(x: pt.x - 14, y: pt.y - 14, width: 28, height: 28)
            if let f = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["vela-place-dot", "vela-place-label"]).first,
               let id = f.attribute(forKey: "id") as? String, let p = model.results.first(where: { $0.id == id }) {
                model.select(p)
                return
            }
            if model.sheet == .directions {
                // Tap an alternate to pick it.
                let c = LatLng(map.convert(pt, toCoordinateFrom: map))
                let metersPerPoint = map.metersPerPoint(atLatitude: c.lat)
                for (i, r) in model.routes.enumerated() where i != model.routeIndex {
                    let cum = Geo.cumulative(r.polyline)
                    if let p = Geo.project(c, on: r.polyline, cum: cum, segments: 0...(r.polyline.count - 2)), p.offMeters < 20 * metersPerPoint {
                        model.routeIndex = i
                        return
                    }
                }
                return
            }
            // A tap on a basemap place label looks the place up by name there.
            let feats = map.visibleFeatures(in: rect).filter { ($0.attribute(forKey: "name") as? String) != nil && $0 is MLNPointFeature }
            if let f = feats.first, let name = f.attribute(forKey: "name") as? String {
                let loc = LatLng(f.coordinate)
                Task { @MainActor in
                    let p = await GoogleMaps.details(Place(id: "tap:\(name)", name: name, location: loc))
                    self.model.select(p)
                }
            }
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
