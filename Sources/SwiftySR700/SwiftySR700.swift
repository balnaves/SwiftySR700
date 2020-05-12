import Foundation
import SwiftSerial
import Logging

enum DecodingState {
    case lookingForHeader1
    case lookingForHeader2
    case packetData
    case lookingForFooter2
}

enum ConnectionState {
    case notConnected
    case attemptingConnect
    case connecting
    case readingCurrentRecipe
    case ready
}

enum ConnectionType {
    case none
    case auto
    case singleShot
}

enum State {
    case idle
    case roast
    case cool
    case sleep
}

enum HeatSetting: UInt8 {
    case none = 0, low, medium, high
}

protocol RoasterDelegate: class {
    func roasterChanged(temperature: Int)
    func disconnected()
}

let logger = Logger(label: "sr700")

// MARK: - Main SwiftySR700 Class

/* Documentation for the communications protocol can be found at:
 https://github.com/Roastero/freshroastsr700/blob/master/docs/communication_protocol.rst
 */

class SwiftySR700 {
    
    var serialPort: SerialPort?
    
    /* if set to True, turns on thermostat mode.  In thermostat
    mode, freshroastsr700 takes control of heat_setting and does
    software PID control to hit the demanded target_temp. Defaults to
    False. */
    fileprivate var softwareThermostat = false

    /* enable direct control over the internal
    heat_controller object.  Defaults to False. When set to True, the
    softwareThermostat field is IGNORED, and assumed to be False.  Direct
    control over the software heater_level means that the freshroastsr700's
    PID controller cannot control the heater.  Since softwareThermostat and
    ext_sw_heater_drive cannot be allowed to both be True, this arg
    is given precedence over the softwareThermostat arg.
     */
    var extHeaterDrive = false
    
    var heaterSegments = 8
    
    var kp = 0.06
    var ki = 0.0075
    var kd = 0.01
    
    fileprivate let tempUnit:[UInt8] = [0x61, 0x74]
    fileprivate let flags:[UInt8] = [0x63]
    fileprivate let footer:[UInt8] = [0xAA, 0xFA]
    
    fileprivate var header:[UInt8] = [0xAA, 0xAA]
    fileprivate var currentState:[UInt8] = [0x02, 0x01]

    fileprivate var fanSpeed: UInt8 = 0 // Valid values are 01, 02, 03, 04, 05, 06, 07, 08, 09 (00 during init)
    
    /*
     Heat Setting (1 byte) - This field is the heat setting for the roaster. This value will not cause the roaster to start roasting.
     It only dictates what the roaster will do once it begins.
     Below is a list of valid values.
     
     00 - No Heat (Cooling)
     01 - Low Heat
     02 - Medium Heat
     03 - High Heat
     */
    fileprivate var heatSetting:HeatSetting = .none
    
    fileprivate var targetTemp = 150
    fileprivate var currentTemp = 150
    
    fileprivate(set) var timeRemaining:Int = 0
    fileprivate(set) var totalTime = 0
    
    fileprivate var doDisconnect = false
    fileprivate var tearDown = false
    
    // for SW PWM heater setting
    fileprivate var heaterLevel = 0
    
    fileprivate var connected = false
    fileprivate var connectState = ConnectionState.notConnected
    fileprivate var attemptingConnect = ConnectionType.none
    fileprivate var readState = DecodingState.lookingForHeader1
    
    fileprivate var responsePacket = [UInt8]()
    
    fileprivate var connectCompletionHandler: ((ConnectionState) -> Void)?
    fileprivate var roastCompletionHandler: (() -> Void)?
    fileprivate var coolCompletionHandler: (() -> Void)?
    
    weak var delegate: RoasterDelegate?

    fileprivate(set) var state = State.idle {
        didSet {
            switch state {
            case .idle:
                currentState = [0x02, 0x01]
                break
            case .roast:
                currentState = [0x04, 0x02]
                break
            case .cool:
                currentState = [0x04, 0x04]
                break
            case .sleep:
                currentState = [0x08, 0x01]
                break
            }
            logger.info("Set state to \(state)")
        }
    }
    
    fileprivate let messageQueue = DispatchQueue(label: "sr700.messageQueue")

    fileprivate let timer = RepeatingTimer(timeInterval: 1)
    
    init() {
        if extHeaterDrive {
            softwareThermostat = false
        }
        messageQueue.async {
            self.commEntry()
        }
        timer.eventHandler = timerFired
    }
    
    func connect(completion: @escaping (ConnectionState) -> Void) {
        connectCompletionHandler = completion
        
        if startConnect(type: .singleShot) == false {
            // We're not in the right state to connect, should we throw an Error here?
            connectCompletionHandler?(.notConnected)
        }
    }
    
    func autoConnect() -> Bool {
        return startConnect(type: .auto)
    }
    
    func roast(level: HeatSetting, fan: UInt8, seconds:Int, completion: @escaping () -> Void) {
        state = .roast
        heatSetting = level
        softwareThermostat = false
        fanSpeed = fan
        timeRemaining = seconds
        roastCompletionHandler = completion
        coolCompletionHandler = nil
    }
    
    func roast(temperature: Int, fan: UInt8, seconds:Int, completion: @escaping () -> Void) {
        state = .roast
        targetTemp = temperature
        softwareThermostat = true
        fanSpeed = fan
        timeRemaining = seconds
        roastCompletionHandler = completion
        coolCompletionHandler = nil
    }
    
    func cool(fan: UInt8, seconds:Int, completion: @escaping () -> Void) {
        state = .cool
        fanSpeed = fan
        timeRemaining = seconds
        coolCompletionHandler = completion
        roastCompletionHandler = nil
    }
    
    func idle() {
        state = .idle
        heatSetting = .none
        fanSpeed = 0
        coolCompletionHandler = nil
        roastCompletionHandler = nil
    }
    
    func sleep() {
        state = .sleep
    }
    
    /// Closes the serial port but does not exit the communications thread, so we are
    /// able to reconnect again if we want to.
    func disconnect() {
        doDisconnect = true // Signals commEntry()
        timer.suspend()
        state = .sleep
    }
    
    /// Closes the serial port and exits the communications thread. If you want to
    /// connect again you'll need to create another roaster
    func terminate() {
        disconnect()
        tearDown = true
    }
    
    fileprivate func startConnect(type: ConnectionType) -> Bool {
        guard connectState == .notConnected else {
            return false
        }
        connected = false
        connectState = .attemptingConnect
        attemptingConnect = type
        return true
    }
    
    fileprivate func internalConnect() throws {
        connectState = .connecting
        serialPort = SerialPort(path: "/dev/ttyUSB0")
        
        do {
            logger.info("Attempting to open port")
            try serialPort?.openPort()
            logger.info("Serial port opened successfully.")
            
            // https://blog.mbedded.ninja/programming/operating-systems/linux/linux-serial-ports-using-c-cpp/#vmin-and-vtime-c_cc
            serialPort?.setSettings(receiveRate: .baud9600,
                                   transmitRate: .baud9600,
                                   minimumBytesToRead: 0,
                                   timeout: 2 // Deciseconds?
            )
        }
        catch PortError.failedToOpen {
            logger.error("Serial port failed to open. You might need root permissions.")
            throw RoasterError.lookupError("Serial port failed to open. You might need root permissions.")
        }
        catch {
            logger.error("Error: \(error)")
            throw RoasterError.lookupError(error.localizedDescription)
        }
        setInitState()
        //logger.info("internalConnect: Read recipe: \(recipe.hexEncodedString())")
    }
        
    fileprivate func setInitState() {
        connectState = .readingCurrentRecipe
        header = [0xAA, 0x55]
        currentState = [0x00, 0x00]
    }
    
    fileprivate func writeToDevice() -> Bool {
        var success = false
        let packet = generatePacket()
        packet.withUnsafeBytes { bytes in
            let unsafeBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: packet.count)
            unsafeBytes.initialize(from: packet, count: packet.count)
            do {
                let bytesWritten = try serialPort?.writeBytes(from: unsafeBytes, size: packet.count)
                logger.info("Wrote \(bytesWritten ?? 0) packet bytes: \(packet.hexEncodedString())")
                success = true
            }
            catch {
                logger.error("Failed to send packet.")
            }
        }
        return success
    }
    
    // Generates a packet based upon the current class variables. Note that
    // current temperature is not sent, as the original application sent zeros
    // to the roaster for the current temperature.
    func generatePacket() -> [UInt8] {
        
        let roasterTime = roundf(timeRemaining.secondsToFloatMinutesRounded() * 10.0)
        
        var bytes = [UInt8]()
        bytes.append(contentsOf: header)
        bytes.append(contentsOf: tempUnit)
        bytes.append(contentsOf: flags)
        bytes.append(contentsOf: currentState)
        bytes.append(UInt8(fanSpeed))
        bytes.append(UInt8(roasterTime))
        bytes.append(UInt8(heatSetting.rawValue))
        bytes.append(contentsOf: [0x00, 0x00]) // Current temp, we don't get to set that
        bytes.append(contentsOf: footer)
        
        return bytes
    }
    
    fileprivate func commEntry() {
        
        logger.info("*** Started communications task ***")
        
        while !tearDown {
            
            // Spin our wheels here until we are asked to connect or terminate
            
            while attemptingConnect == .none {
                if tearDown {
                    break
                }
            }
            if tearDown {
                break
            }
            
            // Now we proceed to connection attempt
            
            connectState = .attemptingConnect
            
            if attemptingConnect == .auto {
                if autoConnect() {
                    connected = true
                    //connectState = .connected
                }
                else {
                    connected = false
                    connectState = .notConnected
                    
                    attemptingConnect = .none
                    continue
                }
            }
            else if attemptingConnect == .singleShot {
                do {
                    try internalConnect()
                    connected = true
                    //connectState = .connected
                }
                catch {
                    connected = false
                    connectState = .notConnected
                    connectCompletionHandler?(.notConnected)
                }
                if connectState != .readingCurrentRecipe {
                    attemptingConnect = .none
                    continue
                }
            }
            else {
                attemptingConnect = .none
            }
            
            logger.info("Starting loop")
            attemptingConnect = .none
            
            // Create a PID controller and heat controller here so
            // we can switch between thermostat mode and heat level mode as desired
            
            let pidc = PID(p: kp, i: ki, d: kd, derivator: 0, integrator: 0, minOutput: 0, maxOutput: Double(heaterSegments))
            let heater = HeatController(segmentCount: heaterSegments)
            
            readState = .lookingForHeader1

            var loopStartTime = Date()
            var writeErrors = 0
            var readErrors = 0
            
            while !doDisconnect {
                loopStartTime = Date()
                //logger.info("Top of loop")

                // Write to device
                
                if writeToDevice() == false {
                    writeErrors += 1
                    if writeErrors > 3 {
                        logger.error("3 write failures, disconnecting")
                        doDisconnect = true
                        continue
                    }
                }
                else {
                    writeErrors = 0
                }
                
                // Read from device
                // The python library reads until there are no more "in_waiting".
                // We're unbuffered so we have to do something else here.
                do {
                    
                    // Until we get a timeout, read bytes and process them
                    
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
                    while true {
                        //logger.info("About to readBytes")
                        if let bytesRead = try serialPort?.readBytes(into: buffer, size: 1), bytesRead == 1 {
                            //logger.info("readBytes read \(bytesRead) bytes")
                            processResponseByte(buffer[0])
                            writeErrors = 0
                        }
                        else {
                            //logger.info("readBytes read no bytes")
                            break // We timed out, done for now
                        }
                    }
                    //logger.info("Deallocating read buffer")
                    buffer.deallocate()
                }
                catch {
                    logger.error("Serial port read failed")
                    readErrors += 1
                    if readErrors > 3 {
                        logger.error("3 read failures, disconnecting")
                        doDisconnect = true
                        continue
                    }
                }
                
                // Update the PID controlled software thermostat, or external thermostat (not implemented)
                if connectState == .ready && softwareThermostat {
                    logger.info("Updating thermostat")
                    if state == .roast {
                        // Update the PID controller once every time through
                        // the heater segment count
                        if heater.aboutToRollOver {
                            if extHeaterDrive {
                                heater.heatLevel = heaterLevel
                            }
                            else {
                                let controllerOutput = pidc.update(currentTemp: Double(currentTemp), targetTemp: Double(targetTemp))
                                logger.info("heater.aboutToRollOver, currentTemp = \(currentTemp), targetTemp = \(targetTemp), controllerOutput (heatLevel) = \(controllerOutput)")
                                heater.heatLevel = Int(controllerOutput)
                            }
                        }
                        // Toggle roaster heat level (Off/L/M/H) between High and off
                        heatSetting = heater.generateBangBang() ? .high : .none
                    }
                    else {
                        heater.heatLevel = 0
                        heaterLevel = 0
                        heatSetting = .none
                    }
                }
                
                // Don't send packet faster than once every 0.25s, so sleep here if we need to
                let elapsedTime = Date().timeIntervalSince(loopStartTime)
                let sleepTime = 0.25 - elapsedTime
                if sleepTime > 0 {
                    Thread.sleep(forTimeInterval: sleepTime)
                }
            }
            
            // Close port and we go back to the top of the loop to spin our wheels
            // until we are asked to connect again....
            serialPort?.closePort()
            doDisconnect = false
            connected = false
            connectState = .notConnected
        }
    }
    
    // Timer used to keep track of the time while roasting or
    // cooling. If the time remaining reaches zero, the roaster will be set to
    // the idle state.
    fileprivate func timerFired() {
        if state == .roast || state == .cool {
            totalTime += 1
            if timeRemaining > 0 {
                timeRemaining -= 1
                logger.info("*** Time remaining = \(timeRemaining), totalTime = \(totalTime) ***")
            }
            else {
                // Time remaining has expired
                logger.info("*** Time remaining expired, setting to idle state, totalTime = \(totalTime) ***")
                if state == .roast {
                    roastCompletionHandler?()
                }
                else if state == .cool {
                    coolCompletionHandler?()
                }
                idle()
            }
        }
    }
    
    fileprivate func processResponseByte(_ byte:UInt8) {
        switch readState {
        case .lookingForHeader1:
            if byte == 0xAA {
                readState = .lookingForHeader2
            }
        case .lookingForHeader2:
            if byte == 0xAA {
                readState = .packetData
                responsePacket = []
            }
            else {
                readState = .lookingForHeader1
            }
        case .packetData:
            if byte == 0xAA {
                // this could be the start of an end of packet marker
                readState = .lookingForFooter2
            }
            else {
                responsePacket.append(byte)
                
                // SR700 FW bug - if current temp is 250 degF (0xFA),
                // the FW does not transmit the footer at all.
                // fake the footer here.
                if responsePacket.count == 10 && byte == 0xFA {
                    logger.info("Temp = 250F. Faking footer due to SR700 firmware bug!")
                    processResponseByte(0xAA)
                    processResponseByte(0xFA)
                }
            }
        case .lookingForFooter2:
            if byte == 0xFA {
                // We have a packet, process it
                let _ = processResponseBody(responsePacket)
                readState = .lookingForHeader1
            }
            else {
                // Last byte was beginning of footer
                responsePacket.append(0xAA)
                readState = .packetData
                processResponseByte(byte)
            }
        }
    }
    
    fileprivate func handleInitCompletion() {
        connectState = .ready
        // Reset to normal header
        header = [0xAA, 0xAA]
        // Reset to idle state
        currentState = [0x02, 0x01]
        // Call our connect completion handler if we have one
        connectCompletionHandler?(.ready)
        timer.resume()
    }
    
    fileprivate func processResponseBody(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 10 else {
            logger.error("Invalid packet length: \(bytes)")
            return false
        }
        logger.info("Processing response bytes, bytes = \(bytes.hexEncodedString())")
        
        // Check to see if we've read the initial recipes
        if connectState == .readingCurrentRecipe {
            if bytes[2] == 0xAF || bytes[2] == 0x00 {
                logger.info("Read end of recipe, we are now fully connected")
                handleInitCompletion()
            }
            return true
        }

        let temp = bytes[8...9].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        //logger.info("Processing roaster bytes, temp bytes = \(bytes[8...9].hexEncodedString())")
        logger.info("Processing roaster bytes, temp = \(temp)")
        
        if temp == 0xFF00 {
            currentTemp = 150
        }
        else if temp > 550 || temp < 150 {
            setInitState()
            return false
        }
        else {
            currentTemp = Int(temp)
        }
        
        // Let our delegate know something changed
        delegate?.roasterChanged(temperature: currentTemp)
        
        return true
    }
}

// MARK: - Int Extension

extension Int {
    /// Converts seconds to minutes as a float rounded to one digit.
    /// Will cap the float minutes at 9.9 (594 seconds).
    func secondsToFloatMinutesRounded() -> Float {
        if self < 594 {
            let floatMins = Float(self) / 60.0 // Convert to minutes
            return (floatMins * 10.0) / 10.0 // Round to 1 digit
        }
        return 9.9
    }
}

// MARK: - Data Extension

extension Data {
    func hexEncodedString() -> String {
        return "[" + map { String(format: "%02hhX", $0) }.joined(separator: ", ") + "]"
    }
}

extension Collection where Element == UInt8 {
    var data: Data {
        return Data(self)
    }
    var uint16: UInt16 {
        return data.withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    func hexEncodedString() -> String {
        return "[" + map { String(format: "%02hhX", $0) }.joined(separator: ", ") + "]"
    }
}
