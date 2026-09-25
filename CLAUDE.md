# CLAUDE.md

Swift driver for the FreshRoast SR700 coffee roaster, plus `Bridge/`, a separate package that serves the roaster to Artisan over WebSocket.

## Layout

- `Sources/SwiftySR700/` — the library (Swift tools 5.1, deps: SwiftSerial, swift-log).
  - `SwiftySR700.swift` — the `SwiftySR700` class: serial read/write loop, packet encoding/decoding, step timer, PID thermostat, public API.
  - `HeatController.swift` — turns a heater level (0...segments) into an on/off bang-bang pattern, since the SR700 only has off/low/medium/high.
  - `PID.swift`, `RepeatingTimer.swift` (a `DispatchSourceTimer` wrapper that tolerates repeated suspend/resume).
- `Tests/SwiftySR700Tests/` — library tests.
- `Examples/SimpleClosure`, `Examples/SimpleDelegate` — standalone packages depending on the GitHub URL, not the local path.
- `Bridge/` — its own package (Swift tools 6.0, Swift 5 language mode, macOS 14+), depends on the library via `.package(path: "..")`.
  - `Sources/SR700BridgeCore/` — server-independent logic: `ArtisanProtocol.swift` (JSON request/response types), `RoasterSession.swift` (an actor holding all session and safety logic), `RoasterControl.swift` (protocol over the `SwiftySR700` API the bridge uses), `SimulatedRoaster.swift`.
  - `Sources/SR700ArtisanBridge/` — Hummingbird WebSocket server and ArgumentParser CLI. Keep it thin; logic belongs in `SR700BridgeCore` where it can be tested.
  - `FreshRoast-SR700.aset` — Artisan settings file matched to the bridge's commands and defaults.
- `../SR700-hardware-testing.md` (outside the repo) — checklist for things that need a real roaster and Artisan.

## Commands

```
# Library, skipping tests that need a roaster on /dev/ttyUSB0
swift test --skip "testConnect|testCool|testHeatLevelSetting|testTemperatureSetting"

# Bridge (uses SimulatedRoaster, no hardware needed)
cd Bridge && swift build && swift test

# Run the bridge without hardware
cd Bridge && swift run SR700ArtisanBridge --simulate --verbose
```

`testConnect`, `testCool`, `testHeatLevelSetting` and `testTemperatureSetting` need a real roaster and fail (after a 30 s timeout) without one. Don't treat those failures as regressions.

## Library conventions

- `SwiftySR700` is used from three places at once: the serial loop on `serialCommunicationsQueue`, the 1 s `RepeatingTimer`, and callers. All state they share (`_state`, fan, heat, target, heater level, thermostat flags, `timeRemaining`, header/currentState) is guarded by `lock` via `withLock { }`. Any new shared state must be too.
- Never call a completion handler or delegate method while holding the lock; copy what's needed out of `withLock` and call afterwards (see `timerFired()` and `processResponseBody`). Callers are allowed to call back into the roaster from callbacks.
- `NSLock` isn't recursive: don't call a public getter/setter from inside `withLock`.
- Step methods (`roast`, `cool`, `idle`) reset the step and completion handler. Live setters (`setFan`, `setHeat`, `setTargetTemperature`, `setHeaterLevel`, `setTimeRemaining`) change the running step without resetting it. Keep that distinction.
- Mode flags: `setHeat` clears thermostat and external drive; `setTargetTemperature` sets thermostat, clears external drive; `setHeaterLevel` sets both (external drive takes precedence over the PID).
- `generatePacket()` is internal and tested directly for byte layout; the protocol reference is Roastero's [communication_protocol.rst](https://github.com/Roastero/freshroastsr700/blob/master/docs/communication_protocol.rst).
- Temperatures are °F. The roaster reports `0xFF00` for below 150 °F, which is mapped to 150. Readings above 550 or below 150 put the driver back into its init/reconnect state.
- The roaster's step timer maxes out at 9.9 minutes (594 s); anything longer must be topped up.
- Code style follows the existing files: 4-space indent, `fileprivate` for internals, `else` on its own line after `}`.

## Bridge conventions

- `RoasterSession` is the only place that talks to the roaster. Everything goes through `RoasterControl` so `SimulatedRoaster` can stand in; add new roaster API to the protocol and the simulator together.
- Every Artisan request gets a reply echoing its `id`. `temp` and `target` are `-1` for "no reading" (disconnected / thermostat not in control).
- Safety behaviour is deliberate and tested: keep the step timer topped up while roasting; force-cool (fan 9, 180 s, then idle) on client disconnect mid-roast, watchdog timeout or no client (both also push `endRoasting`), or shutdown. `tick()` also retries the serial connection every 5 s, because the driver drops to `.notConnected` without a callback. Don't weaken these without being asked.
- On client connect, an idle roaster is reset to the `.aset` ON defaults (fan 5, heat 0, target 150, heater 0), because Artisan's sliders only send when moved. If you change defaults, change the `.aset` file and `Bridge/README.md` too.
- `RoasterSession` takes an injectable `now` clock; tests use it for the watchdog rather than sleeping.

## Docs

`README.md` covers the library, `Bridge/README.md` covers the bridge (options, Artisan setup, protocol, safety). Update the relevant one when changing public API, CLI options, protocol or safety behaviour.
