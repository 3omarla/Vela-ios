import Foundation

/// The OpenFreeMap Liberty style, fetched live so tile paths follow OpenFreeMap's snapshot, then
/// painted in Vela's palettes (app ui/map VelaMapView.kt applyLight / applyDark with MODERN_DARK).
enum MapStyle {
    static let liberty = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    struct Palette {
        let land, water, green, pitch, minor, service, major, motorway, building, buildingLine, aeroway, plaza, label, halo: String
        let dark: Bool
    }

    /// Light: pixel-sampled from the Google app in light mode.
    static let light = Palette(land: "#f8f7f7", water: "#90daee", green: "#d3f8e1", pitch: "#a9eac2",
                               minor: "#aab9c9", service: "#9bacbc", major: "#aab9c9", motorway: "#8aa4c0",
                               building: "#e8e9ed", buildingLine: "#d6d9e6", aeroway: "#eceef1", plaza: "#dbe0e8", label: "#5f6368", halo: "#ffffff", dark: false)

    /// Modern dark.
    static let dark = Palette(land: "#162640", water: "#000d2a", green: "#0d3847", pitch: "#0d4956",
                              minor: "#3d5a77", service: "#2a4056", major: "#476789", motorway: "#476789",
                              building: "#1c3b69", buildingLine: "#2e3d6d", aeroway: "#1d2c48", plaza: "#2a3546", label: "#c3cad6", halo: "#1a2230", dark: true)

    private static func cacheURL(dark: Bool) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(dark ? "style-dark.json" : "style-light.json")
    }

    /// A local file URL of the painted style; the last good copy when the network is down.
    static func load(dark: Bool) async -> URL {
        let cache = cacheURL(dark: dark)
        do {
            var req = URLRequest(url: liberty, timeoutInterval: 10)
            req.setValue(Calibration.velaUA, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard var style = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
            paint(&style, dark ? Self.dark : Self.light)
            let out = try JSONSerialization.data(withJSONObject: style)
            try out.write(to: cache, options: .atomic)
            return cache
        } catch {
            return FileManager.default.fileExists(atPath: cache.path) ? cache : liberty
        }
    }

    static func paint(_ style: inout [String: Any], _ p: Palette) {
        guard var layers = style["layers"] as? [[String: Any]] else { return }
        let motorway: Set = ["road_motorway", "road_motorway_link", "bridge_motorway", "bridge_motorway_link"]
        let major: Set = ["road_trunk_primary", "bridge_trunk_primary"]
        let minor: Set = ["road_secondary_tertiary", "bridge_secondary_tertiary", "road_minor", "road_link", "bridge_street", "bridge_link"]
        let service: Set = ["road_service_track", "bridge_service_track"]
        let greens: Set = ["park", "landcover_grass", "landcover_wood", "landuse_pitch", "landuse_track"]
        let roadLabels: Set = ["highway-name-path", "highway-name-minor", "highway-name-major"]
        for i in layers.indices {
            let id = layers[i]["id"] as? String ?? ""
            let type = layers[i]["type"] as? String ?? ""
            var paint = layers[i]["paint"] as? [String: Any] ?? [:]
            switch id {
            case "background": paint["background-color"] = p.land
            case "water": paint["fill-color"] = p.water
            case "waterway_river", "waterway_other": paint["line-color"] = p.water
            case "park", "landcover_grass", "landcover_wood":
                paint["fill-color"] = p.green; paint["fill-opacity"] = 1; paint.removeValue(forKey: "fill-outline-color")
            case "landuse_pitch", "landuse_track": paint["fill-color"] = p.pitch; paint["fill-opacity"] = 1
            case "building":
                paint["fill-color"] = p.building; paint["fill-outline-color"] = p.buildingLine
                layers[i]["minzoom"] = 15; layers[i]["maxzoom"] = 24
            case "building-3d":
                paint["fill-extrusion-color"] = p.building; paint["fill-extrusion-opacity"] = p.dark ? 0.8 : 1
            case "park_outline": layers[i]["layout"] = ["visibility": "none"]
            // Liberty paints airport grounds a fixed light gray, which glares on the dark map.
            case "aeroway_fill": paint["fill-color"] = p.aeroway; paint["fill-opacity"] = 1
            // Pedestrian plazas carry a light dotted pattern; Google shows them flat.
            case "road_area_pattern": paint.removeValue(forKey: "fill-pattern"); paint["fill-color"] = p.plaza
            default:
                if motorway.contains(id) { paint["line-color"] = p.motorway }
                else if major.contains(id) { paint["line-color"] = p.major }
                else if minor.contains(id) { paint["line-color"] = p.minor }
                else if service.contains(id) { paint["line-color"] = p.service }
                else if id.hasSuffix("_casing") && (id.hasPrefix("road_") || id.hasPrefix("bridge_")) { paint["line-color"] = p.land }
                else if type == "fill" && !greens.contains(id) && (id.hasPrefix("landuse") || id.hasPrefix("landcover")) { paint["fill-color"] = p.land }
                if type == "symbol" {
                    paint["text-color"] = roadLabels.contains(id) ? (p.dark ? "#d0d6e0" : "#3c4043") : p.label
                    paint["text-halo-color"] = p.halo
                    paint["text-halo-width"] = roadLabels.contains(id) ? 1.9 : 1.2
                }
            }
            layers[i]["paint"] = paint
        }
        style["layers"] = layers
    }
}
