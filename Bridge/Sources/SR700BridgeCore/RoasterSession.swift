import Foundation
import Logging
import SwiftySR700

let logger = Logger(label: "sr700.bridge")

/// Owns the roaster on behalf of Artisan: dispatches commands, keeps the
/// SR700's step timer from expiring during an Artisan controlled roast, and
/// cools the roaster if Artisan goes away.
public actor RoasterSession {

    /// The SR700 firmware caps a step at 9.9 minutes
    public static let maxStepSeconds = 594
    public static let defaultRoastFan = 5
    public static let safetyCoolFan = 9
    public static let safetyCoolSeconds = 180

    public typealias PushHandler = @Sendable (String) async -> Void

    let roaster: RoasterControl
    let watchdogInterval: TimeInterval
    let now: @Sendable () -> Date

    private var lastMessage: Date?
    private var activeClient: UUID?
    private var pushHandler: PushHandler?
    private var lastConnectAttempt: Date?
    static let connectRetryInterval: TimeInterval = 5

    public init(roaster: RoasterControl, watchdogInterval: TimeInterval = 10, now: @escaping @Sendable () -> Date = { Date() }) {
        self.roaster = roaster
        self.watchdogInterval = watchdogInterval
        self.now = now
    }

    // MARK: - Clients

    /// Registers a new Artisan connection. Only the latest connection receives push messages.
    public func clientConnected(push: @escaping PushHandler) -> UUID {
        let client = UUID()
        activeClient = client
        pushHandler = push
        lastMessage = now()
        logger.info("Artisan connected")
        // Artisan's sliders only send when moved, so they can't tell us their
        // positions. Start each session from known defaults instead, matching
        // what the settings file's ON action sets the sliders to.
        if roaster.state == .idle {
            roaster.idle()
            roaster.setHeat(.none)
            logger.info("Reset roaster to defaults: fan \(Self.defaultRoastFan) at CHARGE, heat off, manual mode")
        }
        return client
    }

    public func clientDisconnected(_ client: UUID) {
        guard client == activeClient else {
            return
        }
        activeClient = nil
        pushHandler = nil
        logger.info("Artisan disconnected")
        if roaster.state == .roast {
            forceCool(reason: "Artisan disconnected")
        }
    }

    // MARK: - Requests

    /// Handles one JSON message from Artisan and returns the JSON reply
    public func handle(text: String) -> String {
        lastMessage = now()
        guard let request = ArtisanJSON.decodeRequest(text) else {
            logger.warning("Unparseable message: \(text)")
            return ArtisanJSON.encode(ArtisanResponse.failure("invalid request", id: nil))
        }
        return ArtisanJSON.encode(handle(request: request))
    }

    public func handle(request: ArtisanRequest) -> ArtisanResponse {
        lastMessage = now()
        guard let command = ArtisanCommand(rawValue: request.command) else {
            logger.warning("Unknown command: \(request.command)")
            return .failure("unknown command \(request.command)", id: request.id)
        }
        if command != .getData {
            logger.info("\(request.command) \(request.params?.value.map { String($0) } ?? "")")
        }
        let value = request.params?.value

        switch command {
        case .getData:
            return .data(currentData(), id: request.id)

        case .setFan:
            guard let value = value else { return .failure("missing value", id: request.id) }
            roaster.setFan(Int(value.rounded()))

        case .setHeat:
            guard let value = value, let level = HeatSetting(rawValue: UInt8(min(max(value.rounded(), 0), 3))) else {
                return .failure("missing value", id: request.id)
            }
            roaster.setHeat(level)

        case .setTarget:
            guard let value = value else { return .failure("missing value", id: request.id) }
            roaster.setTargetTemperature(Int(value.rounded()))

        case .setHeaterLevel:
            guard let value = value else { return .failure("missing value", id: request.id) }
            roaster.setHeaterLevel(heaterSegments(forPercent: value, segments: roaster.heaterSegments))

        case .roast:
            startRoast(fan: request.params?.fan)

        case .cool:
            cool(fan: request.params?.fan ?? Self.safetyCoolFan,
                 seconds: request.params?.seconds ?? Self.safetyCoolSeconds)

        case .idle:
            roaster.idle()
        }
        return .ok(id: request.id)
    }

    public func currentData() -> RoasterData {
        let connected = roaster.connectionState == .ready
        let mode: String
        if roaster.isThermostatMode {
            mode = roaster.isExternalHeaterDrive ? "external" : "thermostat"
        }
        else {
            mode = "manual"
        }
        return RoasterData(
            temp: connected ? Double(roaster.currentTemperature) : -1,
            target: mode == "thermostat" ? Double(roaster.targetTemperature) : -1,
            fan: roaster.fan,
            heat: Int(roaster.heat.rawValue),
            heaterLevel: heaterPercent(forSegments: roaster.heaterLevelSetting, segments: roaster.heaterSegments),
            state: "\(roaster.state)",
            mode: mode,
            timeRemaining: roaster.timeRemaining,
            connected: connected)
    }

    // MARK: - Periodic work

    /// Call about once per second: reconnects the roaster, keeps the step
    /// timer topped up while Artisan is present and runs the watchdog.
    public func tick() async {
        // The driver drops back to .notConnected on serial errors without
        // telling us, so poll its state rather than relying on callbacks
        if roaster.connectionState == .notConnected,
           lastConnectAttempt.map({ now().timeIntervalSince($0) >= Self.connectRetryInterval }) ?? true {
            lastConnectAttempt = now()
            roaster.connect { state in
                if state == .ready {
                    logger.info("Roaster connected")
                }
                else {
                    logger.warning("Roaster not connected (\(state)), will retry")
                }
            }
        }

        guard roaster.state == .roast else {
            return
        }
        let silence = lastMessage.map { now().timeIntervalSince($0) } ?? .infinity
        if activeClient == nil || silence > watchdogInterval {
            forceCool(reason: activeClient == nil ? "no Artisan connection" : "no message from Artisan for \(Int(silence))s")
            await push(.endRoasting)
        }
        else {
            roaster.setTimeRemaining(Self.maxStepSeconds)
        }
    }

    /// Call before exiting. Cools a running roast and gives the driver time to
    /// send a few packets before the serial port is closed.
    public func shutdown() async {
        guard roaster.state == .roast else {
            return
        }
        forceCool(reason: "bridge shutting down")
        try? await Task.sleep(for: .seconds(2))
    }

    // MARK: - Control

    private func startRoast(fan: Int?) {
        let fanSpeed = fan ?? (roaster.fan > 0 ? roaster.fan : Self.defaultRoastFan)
        if roaster.isThermostatMode {
            // also covers external heater drive, which the driver keeps enabled
            roaster.roast(temperature: roaster.targetTemperature, fan: fanSpeed, seconds: Self.maxStepSeconds, completion: nil)
        }
        else {
            roaster.roast(level: roaster.heat, fan: fanSpeed, seconds: Self.maxStepSeconds, completion: nil)
        }
    }

    private func cool(fan: Int, seconds: Int) {
        let roaster = self.roaster
        roaster.cool(fan: fan, seconds: seconds) {
            roaster.idle()
        }
    }

    private func forceCool(reason: String) {
        logger.warning("Cooling roaster: \(reason)")
        cool(fan: Self.safetyCoolFan, seconds: Self.safetyCoolSeconds)
    }

    private func push(_ message: ArtisanPushMessage) async {
        await pushHandler?(ArtisanJSON.encode(message))
    }
}
