# SR700ArtisanBridge

Connects a FreshRoast SR700 to [Artisan](https://artisan-scope.org) using Artisan's WebSocket device.
The bridge owns the roaster's serial port and runs a small WebSocket server. Artisan connects to it,
reads temperatures on every sample and sends fan/heat commands from its sliders and buttons.

```
SR700 --USB--> SR700ArtisanBridge (ws://127.0.0.1:8080/WebSocket) <--- Artisan (Device: WebSocket)
```

## Running

```
cd Bridge
swift run SR700ArtisanBridge --serial /dev/tty.usbserial-XXXX
```

| Option | Default | |
|---|---|---|
| `--serial` | `/dev/ttyUSB0` | Roaster serial device |
| `--host` | `127.0.0.1` | Use `0.0.0.0` if Artisan runs on another machine |
| `--port` | `8080` | Must match Artisan's WebSocket port |
| `--path` | `WebSocket` | Must match Artisan's WebSocket path |
| `--watchdog` | `10` | Seconds without a message from Artisan before a roast is cooled |
| `--simulate` | off | Use a simulated roaster, no hardware needed |
| `--verbose` | off | Log every request and reply |

The bridge needs Swift 6 and macOS 14 or Linux. It builds on a Raspberry Pi with the Linux toolchain.

## Artisan setup

Load `FreshRoast-SR700.aset` with Help › Load Settings. It sets:

- **Device:** WebSocket, `127.0.0.1:8080/WebSocket`, 1 second sampling, temperatures in °F.
- **Curves:** the SR700's only sensor measures the hot air entering the chamber, not the beans. It is fed to both ET and BT so Artisan's BT-based features (CHARGE/DROP markers, phases, alarms) keep working, but remember that "BT" is air temperature. The ET curve is hidden since it would duplicate BT, and ΔET/ΔBT are off because the air temperature's rate of rise mostly reflects the heater switching. Extra devices plot Fan and Heat (on the RoR axis), Heater %, and the thermostat Target (only while the Target slider is in control).
- **ON:** resets the sliders to Fan 5, Heat 0, Target 150, Heater 0. The bridge resets the idle roaster to the same defaults when Artisan connects, because Artisan's sliders only send a command when moved.
- **Sliders:**
  - Fan (1–9) and Heat (0–3) are manual controls.
  - Target (°F) switches to the driver's own PID thermostat.
  - Heater (0–100 %) drives the heater directly, so Artisan's PID can control it (Config › PID, output to slider 4).
- **Buttons:** START starts the roaster, so you can preheat. CHARGE marks the beans going in; it also starts the roaster if it is not running yet, so loading beans cold and pressing START then CHARGE works too. DROP starts cooling, and COOL END switches the roaster to idle.

## Protocol

Every request from Artisan carries `id` and `roasterID`. The bridge replies to every request with the same `id`.

| Request | Reply |
|---|---|
| `{"command":"getData"}` | `{"id":..,"data":{"temp","target","fan","heat","heaterLevel","state","mode","timeRemaining","connected"}}` |
| `{"command":"setFan","params":{"value":1-9}}` | `{"id":..,"ok":true}` |
| `{"command":"setHeat","params":{"value":0-3}}` | 〃 |
| `{"command":"setTarget","params":{"value":°F}}` | 〃 |
| `{"command":"setHeaterLevel","params":{"value":0-100}}` | 〃 |
| `{"command":"roast"}` / `{"command":"cool"}` / `{"command":"idle"}` | 〃 |

`temp` is the inlet air temperature and is `-1` while the roaster isn't connected. `target` is `-1` unless the driver's thermostat is in control.

## Safety

- The SR700 ends a step when its own timer runs out, and the timer can't be set above 9.9 minutes. While Artisan is connected and roasting, the bridge keeps the timer topped up.
- The bridge switches to cooling (fan 9, 3 minutes, then idle) if any of these happen:
  - Artisan disconnects during a roast.
  - Artisan stops sending messages for `--watchdog` seconds. The bridge also sends `endRoasting` to Artisan, which marks DROP.
  - The bridge is stopped with Ctrl-C or SIGTERM.
