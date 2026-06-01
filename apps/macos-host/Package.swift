// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WidgetDeskHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WidgetDeskHost", targets: ["WidgetDeskHost"]),
        .executable(name: "widgetdesk", targets: ["WidgetDeskCLI"]),
        .executable(name: "widgetdesk-agent", targets: ["WidgetDeskAgent"])
    ],
    targets: [
        .target(
            name: "WidgetDeskCore"
        ),
        .executableTarget(
            name: "WidgetDeskHost",
            dependencies: ["WidgetDeskCore"]
        ),
        .executableTarget(
            name: "WidgetDeskCLI",
            dependencies: ["WidgetDeskCore"]
        ),
        .executableTarget(
            name: "WidgetDeskAgent",
            dependencies: ["WidgetDeskCore"]
        )
    ]
)
