# SwiftySR700
A Swift package to control a FreshRoastSR700 coffee roaster.

## Installing Swift 5 on Raspberry Pi
First, add the swift-arm repo:
```
curl -s https://packagecloud.io/install/repositories/swift-arm/release/script.deb.sh | sudo bash
```
Then, use `apt` to install Swift
```
sudo apt-get install swift5
```

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
        .package(url: "http://github.com/balnaves/SwiftySR700.git", from: "0.1.0")
    ],
```
Add `SwiftySR700` to your main target:
```
    .target(
        name: "MyFirstProject",
        dependencies: ["SwiftySR700"]),
```

## Using the SwiftySR700 library in your project
The SR700 object can be used with closures, delegate callbacks or a combination of both.
For examples, see the example projects, there's one showing each type of usage.
In the simplest case, your `main.swift` might look something like this
```swift
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
```
## History/Origin
Depending on how far it evolves, this project could be considered a port of, or at least heavily inspired by, the python library [FreshRoastSR700](https://github.com/Roastero/freshroastsr700).
For a number of reasons, I wanted to try a version in swift and Roastero's library was a source of information and inspiration. All of the protocol investigation and documentation was done there and used here as a reference.

## Acknowledgements
* This library is based heavily on the work of [FreshRoastSR700](https://github.com/Roastero/freshroastsr700).
* I use the most excellent [SwiftSerial](https://github.com/yeokm1/SwiftSerial) library to handle the serial communications.
