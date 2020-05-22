import XCTest
@testable import SwiftySR700

final class SwiftySR700Tests: XCTestCase, RoasterDelegate {
    func roasterChanged(temperature: Int, timeRemaining: Int) {
       print("roasterChanged, temperature = \(temperature), timeRemaining = \(timeRemaining)")
    }
    
    func stepCompleted(state: State) {
        print("stepCompleted, state = \(state)")
    }
    
    func connected(state: ConnectionState) {
        print("roaster connected")
    }
    
    func disconnected() {
        print("roaster disconnected")
    }
    
    func testCreateHeatControllerGenerate3() {
        let controller = HeatController(segmentCount: 3)
        XCTAssertEqual(controller.outputArray.count, 4)
        XCTAssertEqual(controller.outputArray[0].count, 3)
        XCTAssertEqual(controller.outputArray[0], [false, false, false])
        XCTAssertEqual(controller.outputArray[3], [true, true, true])
    }
    
    func testCreateHeatControllerGenerate4() {
        let controller = HeatController(segmentCount: 4)
        XCTAssertEqual(controller.outputArray.count, 5)
        XCTAssertEqual(controller.outputArray[0].count, 4)
        XCTAssertEqual(controller.outputArray[0], [false, false, false, false])
        XCTAssertEqual(controller.outputArray[4], [true, true, true, true])
    }
    
    func testCreateHeatControllerGenerate8() {
        let controller = HeatController(segmentCount: 8)
        XCTAssertEqual(controller.outputArray.count, 9)
        XCTAssertEqual(controller.outputArray[0].count, 8)
        XCTAssertEqual(controller.outputArray[0], [false, false, false, false, false, false, false, false])
        XCTAssertEqual(controller.outputArray[8], [true, true, true, true, true, true, true, true])
    }
    
    func testPacket() {
        let roaster = SwiftySR700()
        XCTAssertEqual(roaster.generatePacket(), [0xAA,0xAA,0x61,0x74,0x63,0x02,0x01,0x00,0x00,0x00,0x00,0x00,0xAA,0xFA])
    }
    
    func testConnect() {
        let roaster = SwiftySR700()
        roaster.delegate = self
        
        // This will fail unless we have a roaster connected.
        // We should probably create a MockRoaster at some point.
        
        let expectation = self.expectation(description: "testConnect")
        
        roaster.connect() { state in
            XCTAssertEqual(state, .ready)
            roaster.terminate()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 30)
    }

    func testHeatLevelSetting() {
        let roaster = SwiftySR700()
        roaster.delegate = self
        
        // This will fail unless we have a roaster connected.
        // We should probably create a MockRoaster at some point.
        
        let expectation = self.expectation(description: "testHeatSetting")
        
        roaster.connect() { state in
            XCTAssertEqual(state, .ready)
            
            roaster.roast(level: .low, fan: 1, seconds: 30) {
                print("Roast @ heat level complete.")
                roaster.terminate()
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 60)
    }
    
    func testTemperatureSetting() {
        let roaster = SwiftySR700()
        roaster.delegate = self
        
        // This will fail unless we have a roaster connected.
        // We should probably create a MockRoaster at some point.
        
        let expectation = self.expectation(description: "testTemperatureSetting")
        
        roaster.connect() { state in
            XCTAssertEqual(state, .ready)
            
            roaster.roast(temperature: 300, fan: 1, seconds: 30) {
                print("Roast @ temperature complete.")
                roaster.terminate()
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 60)
    }
    
    // The roaster expects that cool will be run after roast,
    // and will not work as expected if ran before.
    // https://github.com/Roastero/freshroastsr700/blob/49cf4961444c0f56d051d5ac5088ace480b54f02/freshroastsr700/__init__.py#L964
    
    func testCool() {
        let roaster = SwiftySR700()
        
        let expectation = self.expectation(description: "testCool")
        
        roaster.connect() { state in
            XCTAssertEqual(state, .ready)
            
            // We need to roast before we can cool
            
            roaster.roast(level: .low, fan: 1, seconds: 20) {
                print("Roast complete.")
                roaster.cool(fan: 6, seconds: 20) {
                    print("Cool complete.")
                    roaster.disconnect()
                    expectation.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 60)
    }

    static var allTests = [
        ("testPacket", testPacket),
        //("testConnect", testConnect),
        //("testHeatLevelSetting", testHeatLevelSetting),
        //("testTemperatureSetting", testTemperatureSetting),
        //("testCool", testCool),
    ]
}
