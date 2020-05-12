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

## Using the SwiftySR700 package in your project
