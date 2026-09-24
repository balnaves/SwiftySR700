import SwiftySR700

/// The subset of the SwiftySR700 API used by the bridge, so a simulated
/// roaster can stand in for real hardware.
public protocol RoasterControl: AnyObject {
    var connectionState: ConnectionState { get }
    var state: State { get }
    /// Degrees F
    var currentTemperature: Int { get }
    /// Degrees F
    var targetTemperature: Int { get }
    var fan: Int { get }
    var heat: HeatSetting { get }
    var heaterLevelSetting: Int { get }
    var heaterSegments: Int { get }
    var isThermostatMode: Bool { get }
    var isExternalHeaterDrive: Bool { get }
    var timeRemaining: Int { get }

    func connect(completion: ((ConnectionState) -> Void)?)
    func roast(level: HeatSetting, fan: Int, seconds: Int, completion: (() -> Void)?)
    func roast(temperature: Int, fan: Int, seconds: Int, completion: (() -> Void)?)
    func cool(fan: Int, seconds: Int, completion: (() -> Void)?)
    func idle()
    func terminate()

    func setFan(_ speed: Int)
    func setHeat(_ level: HeatSetting)
    func setTargetTemperature(_ temperature: Int)
    func setHeaterLevel(_ level: Int)
    func setTimeRemaining(_ seconds: Int)
}

extension SwiftySR700: RoasterControl {}
