import Foundation
import SwiftySR700

/// A stand-in for SwiftySR700 so the bridge and Artisan configuration can be
/// exercised without hardware. Uses a crude first order thermal model.
public final class SimulatedRoaster: RoasterControl, @unchecked Sendable {

    static let ambient = 70.0          // degrees F
    static let maxHeatRate = 6.0       // degrees F per second at full power
    static let lossCoefficient = 0.013 // per second, scaled by fan speed
    static let tickInterval = 0.25     // seconds, same packet rate as the SR700

    public let heaterSegments = 8

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "sr700.simulator")
    private var timer: DispatchSourceTimer?

    private var _connectionState = ConnectionState.notConnected
    private var _state = State.idle
    private var temperature = SimulatedRoaster.ambient
    private var _targetTemperature = 150
    private var _fan = 0
    private var _heat = HeatSetting.none
    private var _heaterLevel = 0
    private var thermostat = false
    private var externalDrive = false
    private var _timeRemaining = 0
    private var elapsed = 0.0
    private var completion: (() -> Void)?

    public init() {}

    deinit {
        timer?.cancel()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - RoasterControl

    public var connectionState: ConnectionState { withLock { _connectionState } }
    public var state: State { withLock { _state } }
    public var currentTemperature: Int { withLock { max(150, Int(temperature.rounded())) } }
    public var targetTemperature: Int { withLock { _targetTemperature } }
    public var fan: Int { withLock { _fan } }
    public var heat: HeatSetting { withLock { _heat } }
    public var heaterLevelSetting: Int { withLock { _heaterLevel } }
    public var isThermostatMode: Bool { withLock { thermostat } }
    public var isExternalHeaterDrive: Bool { withLock { externalDrive } }
    public var timeRemaining: Int { withLock { _timeRemaining } }

    public func connect(completion: ((ConnectionState) -> Void)?) {
        withLock { _connectionState = .connecting }
        queue.asyncAfter(deadline: .now() + 0.5) {
            self.withLock { self._connectionState = .ready }
            self.startTimer()
            completion?(.ready)
        }
    }

    public func roast(level: HeatSetting, fan: Int, seconds: Int, completion: (() -> Void)?) {
        withLock {
            _state = .roast
            _heat = level
            thermostat = false
            _fan = fan
            _timeRemaining = seconds
            self.completion = completion
        }
    }

    public func roast(temperature: Int, fan: Int, seconds: Int, completion: (() -> Void)?) {
        withLock {
            _state = .roast
            _targetTemperature = temperature
            thermostat = true
            _fan = fan
            _timeRemaining = seconds
            self.completion = completion
        }
    }

    public func cool(fan: Int, seconds: Int, completion: (() -> Void)?) {
        withLock {
            _state = .cool
            _fan = fan
            _timeRemaining = seconds
            self.completion = completion
        }
    }

    public func idle() {
        withLock {
            _state = .idle
            _heat = .none
            _fan = 0
            completion = nil
        }
    }

    public func terminate() {
        timer?.cancel()
        timer = nil
        withLock { _connectionState = .notConnected }
    }

    public func setFan(_ speed: Int) {
        withLock { _fan = min(max(speed, 1), 9) }
    }

    public func setHeat(_ level: HeatSetting) {
        withLock {
            thermostat = false
            externalDrive = false
            _heat = level
        }
    }

    public func setTargetTemperature(_ temperature: Int) {
        withLock {
            _targetTemperature = temperature
            externalDrive = false
            thermostat = true
        }
    }

    public func setHeaterLevel(_ level: Int) {
        withLock {
            _heaterLevel = min(max(level, 0), heaterSegments)
            externalDrive = true
            thermostat = true
        }
    }

    public func setTimeRemaining(_ seconds: Int) {
        withLock { _timeRemaining = max(seconds, 0) }
    }

    // MARK: - Simulation

    private func startTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        t.setEventHandler { [weak self] in
            self?.step(dt: Self.tickInterval)
        }
        timer = t
        t.resume()
    }

    /// Advances the model by dt seconds
    func step(dt: Double) {
        let finished: (() -> Void)? = withLock {
            let power: Double
            switch (_state, thermostat, externalDrive) {
            case (.roast, false, _):
                power = Double(_heat.rawValue) / 3
            case (.roast, true, false):
                power = min(max((Double(_targetTemperature) - temperature) / 20, 0), 1)
            case (.roast, true, true):
                power = Double(_heaterLevel) / Double(heaterSegments)
            default:
                power = 0
            }
            let loss = (temperature - Self.ambient) * Self.lossCoefficient * (0.5 + Double(_fan) / 9)
            temperature += (power * Self.maxHeatRate - loss) * dt

            guard _state == .roast || _state == .cool else {
                return nil
            }
            elapsed += dt
            guard elapsed >= 1 else {
                return nil
            }
            elapsed -= 1
            if _timeRemaining > 0 {
                _timeRemaining -= 1
                return nil
            }
            let handler = completion
            completion = nil
            return handler
        }
        finished?()
    }
}
