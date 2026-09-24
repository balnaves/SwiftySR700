import Foundation
import XCTest
import SwiftySR700
@testable import SR700BridgeCore

/// A clock the tests can advance
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 0)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        date += seconds
        lock.unlock()
    }
}

final class SR700BridgeCoreTests: XCTestCase {

    let clock = TestClock()

    func makeSession(watchdog: TimeInterval = 10) -> (RoasterSession, SimulatedRoaster) {
        let roaster = SimulatedRoaster()
        let clock = self.clock
        return (RoasterSession(roaster: roaster, watchdogInterval: watchdog, now: { clock.now }), roaster)
    }

    func decodeReply(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: - Heater mapping

    func testHeaterPercentToSegments() {
        XCTAssertEqual(heaterSegments(forPercent: 0, segments: 8), 0)
        XCTAssertEqual(heaterSegments(forPercent: 50, segments: 8), 4)
        XCTAssertEqual(heaterSegments(forPercent: 100, segments: 8), 8)
        XCTAssertEqual(heaterSegments(forPercent: 120, segments: 8), 8)
        XCTAssertEqual(heaterSegments(forPercent: -5, segments: 8), 0)
        XCTAssertEqual(heaterSegments(forPercent: 70, segments: 8), 6)
    }

    func testHeaterSegmentsToPercent() {
        XCTAssertEqual(heaterPercent(forSegments: 0, segments: 8), 0)
        XCTAssertEqual(heaterPercent(forSegments: 6, segments: 8), 75)
        XCTAssertEqual(heaterPercent(forSegments: 8, segments: 8), 100)
        XCTAssertEqual(heaterPercent(forSegments: 3, segments: 0), 0)
    }

    // MARK: - Protocol

    func testDecodeArtisanRequest() throws {
        // As sent by Artisan's wsport.send(): id and roasterID are appended to the command
        let request = try XCTUnwrap(ArtisanJSON.decodeRequest(#"{"command":"setFan","params":{"value":7},"id":4711,"roasterID":0}"#))
        XCTAssertEqual(request.command, "setFan")
        XCTAssertEqual(request.id, 4711)
        XCTAssertEqual(request.roasterID, 0)
        XCTAssertEqual(request.params?.value, 7)
    }

    func testDecodeFractionalSliderValue() throws {
        let request = try XCTUnwrap(ArtisanJSON.decodeRequest(#"{"command":"setHeaterLevel","params":{"value":62.5},"id":1}"#))
        XCTAssertEqual(request.params?.value, 62.5)
    }

    func testGetDataEchoesIdAndReportsNoReadingWhenDisconnected() async throws {
        let (session, _) = makeSession()
        let reply = try decodeReply(await session.handle(text: #"{"command":"getData","id":42,"roasterID":0}"#))
        XCTAssertEqual(reply["id"] as? Int, 42)
        let data = try XCTUnwrap(reply["data"] as? [String: Any])
        XCTAssertEqual(data["temp"] as? Double, -1)
        XCTAssertEqual(data["target"] as? Double, -1)
        XCTAssertEqual(data["connected"] as? Bool, false)
        XCTAssertEqual(data["state"] as? String, "idle")
    }

    func testUnknownCommandFails() async throws {
        let (session, _) = makeSession()
        let reply = try decodeReply(await session.handle(text: #"{"command":"explode","id":7}"#))
        XCTAssertEqual(reply["id"] as? Int, 7)
        XCTAssertEqual(reply["ok"] as? Bool, false)
    }

    func testInvalidJSONFails() async throws {
        let (session, _) = makeSession()
        let reply = try decodeReply(await session.handle(text: "not json"))
        XCTAssertEqual(reply["ok"] as? Bool, false)
    }

    // MARK: - Commands

    func testSetters() async throws {
        let (session, roaster) = makeSession()

        var reply = try decodeReply(await session.handle(text: #"{"command":"setFan","params":{"value":7},"id":1}"#))
        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(reply["id"] as? Int, 1)
        XCTAssertEqual(roaster.fan, 7)

        _ = await session.handle(text: #"{"command":"setHeat","params":{"value":2},"id":2}"#)
        XCTAssertEqual(roaster.heat, .medium)
        XCTAssertFalse(roaster.isThermostatMode)

        _ = await session.handle(text: #"{"command":"setTarget","params":{"value":420},"id":3}"#)
        XCTAssertEqual(roaster.targetTemperature, 420)
        XCTAssertTrue(roaster.isThermostatMode)
        XCTAssertFalse(roaster.isExternalHeaterDrive)

        _ = await session.handle(text: #"{"command":"setHeaterLevel","params":{"value":75},"id":4}"#)
        XCTAssertEqual(roaster.heaterLevelSetting, 6)
        XCTAssertTrue(roaster.isExternalHeaterDrive)

        reply = try decodeReply(await session.handle(text: #"{"command":"getData","id":5}"#))
        let data = try XCTUnwrap(reply["data"] as? [String: Any])
        XCTAssertEqual(data["fan"] as? Int, 7)
        XCTAssertEqual(data["heaterLevel"] as? Int, 75)
        XCTAssertEqual(data["mode"] as? String, "external")
        XCTAssertEqual(data["target"] as? Double, -1)
    }

    func testTargetReportedOnlyInThermostatMode() async throws {
        let (session, _) = makeSession()
        _ = await session.handle(text: #"{"command":"setTarget","params":{"value":420},"id":1}"#)
        var data = await session.currentData()
        XCTAssertEqual(data.target, 420)
        _ = await session.handle(text: #"{"command":"setHeat","params":{"value":1},"id":2}"#)
        data = await session.currentData()
        XCTAssertEqual(data.target, -1)
    }

    func testMissingValueFails() async throws {
        let (session, roaster) = makeSession()
        let reply = try decodeReply(await session.handle(text: #"{"command":"setFan","id":1}"#))
        XCTAssertEqual(reply["ok"] as? Bool, false)
        XCTAssertEqual(roaster.fan, 0)
    }

    func testRoastUsesDefaultFanAndFullStep() async {
        let (session, roaster) = makeSession()
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        XCTAssertEqual(roaster.state, .roast)
        XCTAssertEqual(roaster.fan, RoasterSession.defaultRoastFan)
        XCTAssertEqual(roaster.timeRemaining, RoasterSession.maxStepSeconds)
    }

    func testRoastWhileRoastingKeepsSettings() async {
        // START begins the roast (preheat), then CHARGE sends roast again
        let (session, roaster) = makeSession()
        _ = await session.handle(text: #"{"command":"setFan","params":{"value":7},"id":1}"#)
        _ = await session.handle(text: #"{"command":"setTarget","params":{"value":380},"id":2}"#)
        _ = await session.handle(text: #"{"command":"roast","id":3}"#)
        roaster.setTimeRemaining(100)
        _ = await session.handle(text: #"{"command":"roast","id":4}"#)
        XCTAssertEqual(roaster.state, .roast)
        XCTAssertEqual(roaster.fan, 7)
        XCTAssertEqual(roaster.targetTemperature, 380)
        XCTAssertTrue(roaster.isThermostatMode)
        XCTAssertEqual(roaster.timeRemaining, RoasterSession.maxStepSeconds)
    }

    func testCoolThenIdle() async {
        let (session, roaster) = makeSession()
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        _ = await session.handle(text: #"{"command":"cool","params":{"seconds":0},"id":2}"#)
        XCTAssertEqual(roaster.state, .cool)
        XCTAssertEqual(roaster.fan, RoasterSession.safetyCoolFan)
        // the cool step completes after its time runs out, then the roaster idles
        roaster.step(dt: 1)
        XCTAssertEqual(roaster.state, .idle)
    }

    // MARK: - Timer top up and watchdog

    func testTickKeepsRoastTimerToppedUp() async {
        let (session, roaster) = makeSession()
        _ = await session.clientConnected { _ in }
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        roaster.setTimeRemaining(30)
        clock.advance(1)
        await session.tick()
        XCTAssertEqual(roaster.state, .roast)
        XCTAssertEqual(roaster.timeRemaining, RoasterSession.maxStepSeconds)
    }

    func testWatchdogCoolsWhenArtisanGoesQuiet() async {
        let (session, roaster) = makeSession(watchdog: 10)
        let pushed = PushRecorder()
        _ = await session.clientConnected { await pushed.append($0) }
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)

        clock.advance(5)
        await session.tick()
        XCTAssertEqual(roaster.state, .roast)

        clock.advance(6)
        await session.tick()
        XCTAssertEqual(roaster.state, .cool)
        let messages = await pushed.messages
        XCTAssertEqual(messages, [#"{"pushMessage":"endRoasting"}"#])
    }

    func testDisconnectDuringRoastCools() async {
        let (session, roaster) = makeSession()
        let client = await session.clientConnected { _ in }
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        await session.clientDisconnected(client)
        XCTAssertEqual(roaster.state, .cool)
    }

    func testConnectResetsIdleRoasterToDefaults() async {
        let (session, roaster) = makeSession()
        roaster.setFan(8)
        roaster.setTargetTemperature(420)
        _ = await session.clientConnected { _ in }
        XCTAssertEqual(roaster.fan, 0)
        XCTAssertEqual(roaster.heat, HeatSetting.none)
        XCTAssertFalse(roaster.isThermostatMode)
        // CHARGE then uses the default fan, matching the ON action's slider reset
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        XCTAssertEqual(roaster.fan, RoasterSession.defaultRoastFan)
    }

    func testConnectDoesNotResetDuringRoast() async {
        let (session, roaster) = makeSession()
        _ = await session.clientConnected { _ in }
        _ = await session.handle(text: #"{"command":"setFan","params":{"value":8},"id":1}"#)
        _ = await session.handle(text: #"{"command":"roast","id":2}"#)
        _ = await session.clientConnected { _ in }
        XCTAssertEqual(roaster.state, .roast)
        XCTAssertEqual(roaster.fan, 8)
    }

    func testStaleClientDisconnectIsIgnored() async {
        let (session, roaster) = makeSession()
        let first = await session.clientConnected { _ in }
        _ = await session.clientConnected { _ in }
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        await session.clientDisconnected(first)
        XCTAssertEqual(roaster.state, .roast)
    }

    func testRoastWithoutClientIsCooledOnTick() async {
        let (session, roaster) = makeSession()
        _ = await session.handle(text: #"{"command":"roast","id":1}"#)
        await session.tick()
        XCTAssertEqual(roaster.state, .cool)
    }

    // MARK: - Simulator

    func testSimulatorHeatsWhileRoastingAndCoolsAfter() {
        let roaster = SimulatedRoaster()
        roaster.setHeat(.high)
        roaster.roast(level: .high, fan: 5, seconds: 600, completion: nil)
        for _ in 0..<(4 * 120) {
            roaster.step(dt: 0.25)
        }
        let hot = roaster.currentTemperature
        XCTAssertGreaterThan(hot, 350)
        XCTAssertLessThan(hot, 550)

        roaster.cool(fan: 9, seconds: 600, completion: nil)
        for _ in 0..<(4 * 60) {
            roaster.step(dt: 0.25)
        }
        XCTAssertLessThan(roaster.currentTemperature, hot - 100)
    }
}

actor PushRecorder {
    var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
    }
}
