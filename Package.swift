// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacOSMonitorPlugins",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MonitorBar",
            path: "Sources/MonitorBar"
        )
    ]
)
