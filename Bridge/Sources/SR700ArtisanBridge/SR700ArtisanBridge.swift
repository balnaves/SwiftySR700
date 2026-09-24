import ArgumentParser
import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import SR700BridgeCore
import SwiftySR700

/// Serves a FreshRoast SR700 to Artisan's WebSocket device (Config > Device > WebSocket).
@main
struct SR700ArtisanBridge: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Connects a FreshRoast SR700 to Artisan over WebSocket.")

    @Option(help: "Serial device of the roaster.")
    var serial = "/dev/ttyUSB0"

    @Option(help: "Address to listen on. Use 0.0.0.0 to accept connections from other machines.")
    var host = "127.0.0.1"

    @Option(help: "TCP port to listen on (Artisan's WebSocket port setting).")
    var port = 8080

    @Option(help: "WebSocket path (Artisan's WebSocket path setting).")
    var path = "WebSocket"

    @Option(help: "Seconds without a message from Artisan before a roast is cooled.")
    var watchdog: Double = 10

    @Flag(help: "Use a simulated roaster instead of the serial port.")
    var simulate = false

    @Flag(help: "Log every request and reply.")
    var verbose = false

    func run() async throws {
        let level: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
        }
        let logger = Logger(label: "sr700.bridge.server")

        let roaster: RoasterControl = simulate ? SimulatedRoaster() : SwiftySR700(serialPath: serial)
        let session = RoasterSession(roaster: roaster, watchdogInterval: watchdog)

        let router = Router(context: BasicWebSocketRequestContext.self)
        router.ws(RouterPath(path)) { inbound, outbound, context in
            let client = await session.clientConnected { text in
                try? await outbound.write(.text(text))
            }
            do {
                for try await message in inbound.messages(maxSize: 1 << 16) {
                    guard case .text(let text) = message else {
                        continue
                    }
                    let reply = await session.handle(text: text)
                    context.logger.debug("\(text) -> \(reply)")
                    try await outbound.write(.text(reply))
                }
            }
            catch {
                context.logger.warning("WebSocket error: \(error)")
            }
            await session.clientDisconnected(client)
        }

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(address: .hostname(host, port: port), serverName: "SR700ArtisanBridge"),
            logger: logger)

        logger.info("Serving \(simulate ? "simulated roaster" : serial) at ws://\(host):\(port)/\(path)")

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Returns on SIGINT/SIGTERM
            group.addTask {
                try await app.runService()
            }
            group.addTask {
                while !Task.isCancelled {
                    await session.tick()
                    try await Task.sleep(for: .seconds(1))
                }
            }
            try await group.next()
            group.cancelAll()
        }

        await session.shutdown()
        roaster.terminate()
    }
}
