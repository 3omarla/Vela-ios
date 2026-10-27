import Foundation

/// The scraper's moving parts (core config/Calibration.kt). Compiled from the Android repo's
/// calibration.json; positional paths a bundle does not carry fall back to [defaultPaths].
enum Calibration {
    static let userAgent = CalibrationDefaults.userAgent
    static let secChUa = CalibrationDefaults.secChUa
    static let searchEndpoint = CalibrationDefaults.searchEndpoint
    static let searchPb = CalibrationDefaults.searchPb
    static let directionsEndpoint = CalibrationDefaults.directionsEndpoint
    static let directionsPb = CalibrationDefaults.directionsPb
    static let sessionWarmUrl = CalibrationDefaults.sessionWarmUrl

    static let suggestEndpoint = "https://www.google.com/s?tbm=map&gs_ri=maps&suggest=p&authuser=0&hl=en&gl=us"
    static let suggestPb = "!2i5!4m12!1m3!1d{SPAN}!2d{LNG}!3d{LAT}!2m3!1f0!2f0!3f0!3m2!1i{W}!2i{H}!4f13.1" +
        "!7i20!10b1!12m6!1m2!18b1!30b1!2m2!1i203!2i100!19m4!1m3!1i1!2i1!3i1!20m1!1e1"

    static let suggestPaths: [String: [Int]] = [
        "rows": [0, 1], "title": [0, 0], "primary": [1, 0], "secondary": [2, 0],
        "lat": [11, 2], "lng": [11, 3], "lat2": [13, 0, 3, 2], "lng2": [13, 0, 3, 3],
        "featureId": [13, 0, 0],
    ]

    static let directionsPaths: [String: [Int]] = [
        "routes": [0, 1], "geometries": [0, 7], "summary": [0], "distance": [2, 0], "typical": [3, 0],
        "traffic": [10, 0, 0], "typicalLow": [10, 4, 0], "typicalHigh": [10, 4, 1],
        "start": [7, 3, 2], "end": [7, 3, 3], "summaryText": [1], "spans": [3, 5, 0],
    ]

    static let defaultPaths: [String: [Int]] = [
        "results": [64], "single": [0, 1, 0, 14], "atThisPlace": [0, 1, 0, 14, 68], "similar": [2, 11, 0],
        "name": [1, 11], "lat": [1, 9, 2], "lng": [1, 9, 3], "address": [1, 39], "addressComponents": [1, 2],
        "category": [1, 13, 0], "rating": [1, 4, 7], "reviewCount": [1, 4, 8], "priceText": [1, 4, 2],
        "fuelPrice": [1, 88, 0], "website": [1, 7, 0], "actionLabel": [1, 75, 0, 0, 5, 0],
        "actionUrl": [1, 75, 0, 0, 5, 1, 2, 0], "phone": [1, 178, 0, 0], "featureId": [1, 10], "placeId": [1, 78],
        "photos": [1, 72, 0], "featuredReview": [1, 142, 1, 0, 1, 0, 0], "about": [1, 100, 1],
        "editorialSummary": [1, 32, 1, 1], "openStatus": [1, 203, 1, 8, 0], "statusRich": [1, 203, 1, 4, 0],
        "status118": [1, 118, 0, 3, 1, 4, 0], "hours203": [1, 203, 0], "hours118": [1, 118, 0, 3, 0],
        "departments": [1, 118], "closedFlag": [1, 23], "alsoSearched": [0, 1, 0, 14, 99, 0, 0, 1],
    ]

    static let paths: [String: [Int]] = defaultPaths.merging(CalibrationDefaults.paths) { _, remote in remote }

    /// Contactable identifier the community services' usage policies ask for.
    static let velaUA = "Vela-iOS/0.1 (+https://github.com/PimpinPumpkin/Vela)"
}
