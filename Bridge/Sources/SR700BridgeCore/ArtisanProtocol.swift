import Foundation

/* JSON messages exchanged with Artisan's WebSocket device (device 111).
 Artisan adds "id" and "roasterID" to every request and waits up to its
 request timeout (0.5s by default) for a reply carrying the same "id".
 See artisanlib/wsport.py in the Artisan sources. */

public struct ArtisanRequest: Decodable, Equatable {
    public var id: Int?
    public var roasterID: Int?
    public var command: String
    public var params: Params?

    public struct Params: Decodable, Equatable {
        /// Slider value for the set* commands
        public var value: Double?
        /// Optional overrides for roast/cool
        public var fan: Int?
        public var seconds: Int?
    }
}

public enum ArtisanCommand: String {
    case getData
    case setFan
    case setHeat
    case setTarget
    case setHeaterLevel
    case roast
    case cool
    case idle
}

/// Readings returned in reply to getData. Temperatures are in degrees F,
/// -1 means no reading (Artisan's convention for a missing value).
public struct RoasterData: Encodable, Equatable {
    /// The SR700's only sensor, which measures the hot air entering the
    /// chamber, not the beans
    public var temp: Double
    /// Thermostat target, or -1 unless the driver's thermostat is in control
    public var target: Double
    public var fan: Int
    public var heat: Int
    /// Heater drive in percent (0-100)
    public var heaterLevel: Int
    /// "idle", "roast", "cool" or "sleep"
    public var state: String
    /// "manual", "thermostat" or "external"
    public var mode: String
    public var timeRemaining: Int
    public var connected: Bool
}

public struct ArtisanResponse: Encodable, Equatable {
    public var id: Int?
    public var data: RoasterData?
    public var ok: Bool?
    public var error: String?

    public static func data(_ data: RoasterData, id: Int?) -> ArtisanResponse {
        ArtisanResponse(id: id, data: data)
    }

    public static func ok(id: Int?) -> ArtisanResponse {
        ArtisanResponse(id: id, ok: true)
    }

    public static func failure(_ message: String, id: Int?) -> ArtisanResponse {
        ArtisanResponse(id: id, ok: false, error: message)
    }
}

/// Unsolicited message pushed to Artisan, e.g. {"pushMessage":"endRoasting"} marks DROP
public struct ArtisanPushMessage: Encodable, Equatable {
    public var pushMessage: String

    public static let startRoasting = ArtisanPushMessage(pushMessage: "startRoasting")
    public static let endRoasting = ArtisanPushMessage(pushMessage: "endRoasting")
}

enum ArtisanJSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func decodeRequest(_ text: String) -> ArtisanRequest? {
        try? JSONDecoder().decode(ArtisanRequest.self, from: Data(text.utf8))
    }
}

/// Converts a heater percentage (0-100) to a segment count (0...segments)
public func heaterSegments(forPercent percent: Double, segments: Int) -> Int {
    let clamped = min(max(percent, 0), 100)
    return Int((clamped / 100 * Double(segments)).rounded())
}

/// Converts a segment count (0...segments) to a heater percentage (0-100)
public func heaterPercent(forSegments level: Int, segments: Int) -> Int {
    guard segments > 0 else { return 0 }
    return Int((Double(level) / Double(segments) * 100).rounded())
}
