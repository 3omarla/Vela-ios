import Foundation
import CoreLocation

struct LatLng: Codable, Hashable {
    var lat: Double
    var lng: Double

    init(_ lat: Double, _ lng: Double) { self.lat = lat; self.lng = lng }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lng = c.longitude }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case drive, bicycle, walk
    var id: String { rawValue }

    var googleCode: Int {
        switch self {
        case .drive: return 0
        case .bicycle: return 1
        case .walk: return 2
        }
    }

    var osrmBackend: String {
        switch self {
        case .drive: return "routed-car"
        case .bicycle: return "routed-bike"
        case .walk: return "routed-foot"
        }
    }

    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .bicycle: return "bicycle"
        case .walk: return "figure.walk"
        }
    }
}

struct Department: Codable, Hashable {
    var name: String
    var hours: [String]
    var statusText: String?
    var openNow: Bool?
}

struct AboutSection: Codable, Hashable {
    var title: String
    var items: [String]
}

struct Place: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var location: LatLng
    var category: String?
    var address: String?
    var rating: Double?
    var reviewCount: Int?
    var priceText: String?
    var website: String?
    var phone: String?
    var actionUrl: String?
    var actionLabel: String?
    var openNow: Bool?
    var statusText: String?
    var permanentlyClosed = false
    var temporarilyClosed = false
    var hours: [String] = []
    var departments: [Department] = []
    var photoUrls: [String] = []
    var featuredReview: String?
    var featureId: String?
    var placeId: String?
    var about: [AboutSection] = []
    var editorialSummary: String?
    var fuelPrice: String?
    var distanceMeters: Double?
}

struct SearchResult {
    var query: String
    var places: [Place]
    var focusedSingle = false
}

struct SuggestResult {
    var places: [Place]
    var queries: [String]
}

enum ManeuverType: String, Codable {
    case depart, arrive, straight
    case turnLeft, turnRight, slightLeft, slightRight, sharpLeft, sharpRight
    case uturn, merge, forkLeft, forkRight, rampLeft, rampRight, keepLeft, keepRight
    case roundabout, unknown

    var symbol: String {
        switch self {
        case .depart: return "location.north.fill"
        case .arrive: return "mappin.circle.fill"
        case .straight, .unknown: return "arrow.up"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .slightLeft, .keepLeft, .forkLeft, .rampLeft: return "arrow.up.left"
        case .slightRight, .keepRight, .forkRight, .rampRight: return "arrow.up.right"
        case .sharpLeft: return "arrow.down.left"
        case .sharpRight: return "arrow.down.right"
        case .uturn: return "arrow.uturn.down"
        case .merge: return "arrow.merge"
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        }
    }
}

struct Maneuver: Codable, Hashable {
    var type: ManeuverType
    var instruction: String
    var location: LatLng
    /// Length of the step that starts at this maneuver.
    var distanceMeters: Double
    /// Meters along the route polyline where the maneuver sits; filled by [Route.indexManeuvers].
    var alongMeters: Double = 0
    var road: String?
    var laneHint: String?
}

struct TrafficSpan: Codable, Hashable {
    /// 1 = moderate, 2 = heavy, 3 = stopped.
    var level: Int
    var startMeters: Double
    var lengthMeters: Double
}

enum RouteSource: String, Codable {
    case googleHybrid, googleNamed, osrm
}

struct Route: Codable, Hashable, Identifiable {
    var id = UUID()
    var source: RouteSource
    var mode: TravelMode
    var polyline: [LatLng]
    var maneuvers: [Maneuver]
    var distanceMeters: Double
    var durationSeconds: Double
    var durationInTrafficSeconds: Double?
    var summary: String?
    var trafficSpans: [TrafficSpan] = []
    var typicalLowSeconds: Double?
    var typicalHighSeconds: Double?

    var bestDuration: Double { durationInTrafficSeconds ?? durationSeconds }

    /// Delay over the no-traffic time, seconds; zero when Google sent no live figure.
    var trafficDelay: Double { max(0, (durationInTrafficSeconds ?? durationSeconds) - durationSeconds) }
}
