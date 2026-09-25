# SwiftySR700
A Swift package to control a FreshRoast SR700 coffee roaster over its USB serial port.

- Fixed heat roasting (off/low/medium/high), or a software PID thermostat that holds a target temperature.
- Direct heater drive, so an external controller (such as Artisan's PID) can set the heater level.
- Live control: change fan, heat, target, heater level and time remaining mid-roast, from any thread.
- Closure and delegate callbacks for connection, temperature updates and completed steps.
- [SR700ArtisanBridge](Bridge/README.md): a WebSocket server that connects the roaster to [Artisan](https://artisan-scope.org).

## Repository layout

| Path | |
|---|---|
| `Sources/SwiftySR700` | The library |
| `Tests/SwiftySR700Tests` | Library tests (some need a roaster attached, see [Running the tests](#running-the-tests)) |
| `Examples/SimpleClosure`, `Examples/SimpleDelegate` | Small executables showing each callback style |
| `Bridge` | `SR700ArtisanBridge`, a separate package that serves the roaster to Artisan, plus an Artisan settings file |

## Requirements
- The library needs Swift 5.1 or later on macOS or Linux (including Raspberry Pi).
- The bridge needs Swift 6 and macOS 14 or Linux.
- On macOS the roaster's CH340 USB serial chip needs WCH's CH34x driver. The roaster then appears as `/dev/cu.wchusbserial<port>`, where the number depends on the USB port. On Linux it is usually `/dev/ttyUSB0`, and your user needs to be in the `dialout` group.

### Installing Swift on a Raspberry Pi
Swift.org publishes aarch64 Linux toolchains, which run on 64-bit Raspberry Pi OS. Follow the Linux instructions at [swift.org/install](https://www.swift.org/install/).

## Creating a Swift Project
```
mkdir MyFirstProject
cd MyFirstProject
swift package init --type=executable
swift run
```

## Adding the SwiftySR700 package to your project
Edit your `Package.swift` file to add the SwiftySR700 module as a dependency:
```
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/balnaves/SwiftySR700.git", from: "0.1.0")
    ],
```
Add `SwiftySR700` to your main target:
```
    .target(
        name: "MyFirstProject",
        dependencies: ["SwiftySR700"]),
```
The live control API isn't in a tagged release yet. To use it, depend on the `artisan-websocket-bridge` branch:
```
        .package(url: "https://github.com/balnaves/SwiftySR700.git", branch: "artisan-websocket-bridge")
```

## Using the SwiftySR700 library in your project
A SwiftySR700 object can be used with closures, delegate callbacks or a combination of both.
For examples, see the example projects, there's one showing each type of usage.
In the simplest case, your `main.swift` might look something like this
```swift
import Foundation
import Dispatch
import SwiftySR700

class RoastController {
    
    let roaster = SwiftySR700(serialPath: "/dev/ttyUSB0")
    
    func start() {
        roaster.connect { connectionState in
            if connectionState == .ready {
                self.roaster.roast(temperature: 200, fan: 5, seconds: 30) {
                    self.roaster.terminate()
                    exit(EXIT_SUCCESS)
                }
            }
            else {
                print("Roaster not ready, state = \(connectionState)")
                exit(EXIT_FAILURE)
            }
        }
    }
}

let controller = RoastController()
controller.start()
dispatchMain() // Keep our executable running until we exit()
```

`serialPath` defaults to `/dev/ttyUSB0`. On macOS pass the roaster's device, e.g. `SwiftySR700(serialPath: "/dev/cu.wchusbserial20120")`.

### Roast steps
Each of these starts a step. The step's timer counts down once a second, and when it reaches zero the completion closure and `delegate.stepCompleted(state:)` are called.

| Method | |
|---|---|
| `roast(level:fan:seconds:completion:)` | Roast at a fixed heat setting (`.none`, `.low`, `.medium`, `.high`) |
| `roast(temperature:fan:seconds:completion:)` | Roast with the software PID thermostat holding a target temperature (°F) |
| `cool(fan:seconds:completion:)` | Cool with the heater off |
| `idle()` | Stop roasting or cooling |
| `sleep()` | Put the roaster to sleep |

Fan speeds are 1–9. The roaster's own timer can't go above 9.9 minutes, so longer roasts need the time topped up with `setTimeRemaining(_:)`.

### Live control
These change the running step without restarting its timer or replacing its completion handler. They are safe to call from any thread.

| Method | |
|---|---|
| `setFan(_:)` | Fan speed, clamped to 1–9 |
| `setHeat(_:)` | Fixed heat setting. Turns off the thermostat and external heater drive |
| `setTargetTemperature(_:)` | Thermostat target in °F. Turns on the software PID thermostat |
| `setHeaterLevel(_:)` | Drives the heater directly at `0...heaterSegments` (default 8 segments), bypassing the internal PID |
| `setTimeRemaining(_:)` | Seconds left in the current step |

The current settings can be read back, also from any thread: `state`, `connectionState`, `currentTemperature`, `targetTemperature`, `fan`, `heat`, `heaterLevelSetting`, `isThermostatMode`, `isExternalHeaterDrive` and `timeRemaining`.

The SR700's only temperature sensor measures the hot air going into the chamber, not the beans. It never reports below 150 °F.

### Delegate
Set `roaster.delegate` to an object conforming to `RoasterDelegate` to receive:
- `connected(state:)` and `disconnected()`
- `roasterChanged(temperature:timeRemaining:)`, about four times a second while connected
- `stepCompleted(state:)` when a roast or cool step's timer runs out

Callbacks arrive on the library's background queues, not the main thread.

## Running the tests
```
swift test
```
`testConnect`, `testCool`, `testHeatLevelSetting` and `testTemperatureSetting` talk to a real roaster on `/dev/ttyUSB0` and fail without one. To run only the tests that don't need hardware:
```
swift test --skip "testConnect|testCool|testHeatLevelSetting|testTemperatureSetting"
```
The bridge has its own tests, which use a simulated roaster: `cd Bridge && swift test`.

## Using the SR700 with Artisan
The `Bridge` folder contains `SR700ArtisanBridge`, which connects the roaster to [Artisan](https://artisan-scope.org) over Artisan's WebSocket device, together with a matching Artisan settings file (`FreshRoast-SR700.aset`).

```
cd Bridge
swift run SR700ArtisanBridge --serial /dev/cu.wchusbserial20120
```

Add `--simulate` to try it without a roaster. See [Bridge/README.md](Bridge/README.md) for the options, Artisan setup, protocol and safety behaviour.

## History/Origin
Depending on how far it evolves, this project could be considered a port of, or at least heavily inspired by, the python library [FreshRoastSR700](https://github.com/Roastero/freshroastsr700).
For a number of reasons, I wanted to try a version in swift and Roastero's library was a source of information and inspiration. All of the protocol investigation and documentation was done there and used here as a reference.

## Acknowledgements
* This library is based heavily on the work of [FreshRoastSR700](https://github.com/Roastero/freshroastsr700).
* I use the most excellent [SwiftSerial](https://github.com/yeokm1/SwiftSerial) library to handle the serial communications.
* The bridge uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) for its WebSocket server.
