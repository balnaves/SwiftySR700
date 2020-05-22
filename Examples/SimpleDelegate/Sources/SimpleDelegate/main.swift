import Foundation
import Dispatch
import SwiftySR700

class RoastController {
    
    let roaster = SwiftySR700()
    
    func start() {
        roaster.delegate = self
        roaster.connect()
    }
}

/// Delegate callbacks will be called from the serialCommunicationsQueue in the
/// SR700 library, so if something needs to happen on the main thread you're
/// responsible for dispatching it
extension RoastController: RoasterDelegate {
    
    func connected(state: ConnectionState) {
        DispatchQueue.main.async {
            if state == .ready {
                print("connected: Roaster ready")
                // Roaster is ready, do a roast step
                // The roaster will enter a cooling period
                // automatically afterwards
                self.roaster.roast(temperature: 200, fan: 5, seconds: 30)
            }
            else {
                print("connected: Roaster not ready")
                exit(EXIT_FAILURE)
            }
        }
    }
    
    func disconnected() {
        print("disconnected")
        exit(EXIT_FAILURE)
    }
    
    func roasterChanged(temperature: Int, timeRemaining: Int) {
        print("roasterChanged: temperature = \(temperature), timeRemaining = \(timeRemaining)")
    }
    
    func stepCompleted(state: State) {
        print("stepCompleted: state = \(state)")
        roaster.terminate()
        exit(EXIT_SUCCESS)
    }
}

let controller = RoastController()
controller.start()
dispatchMain() // Keep our executable running until we exit()
