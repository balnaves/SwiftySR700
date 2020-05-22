import Foundation
import Dispatch
import SwiftySR700

class RoastController {
    
    let roaster = SwiftySR700()
    
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
