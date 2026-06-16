// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ThermoMole",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ThermoMole", targets: ["ThermoMole"]),
        .executable(name: "ThermoMoleCLI", targets: ["ThermoMoleCLI"]),
        .executable(name: "ThermoMoleCoreCheck", targets: ["ThermoMoleCoreCheck"]),
        .library(name: "ThermoMoleCore", targets: ["ThermoMoleCore"])
    ],
    targets: [
        .target(
            name: "ThermoMoleSMC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "ThermoMoleCore",
            dependencies: []
        ),
        .target(
            name: "ThermoMoleNative",
            dependencies: ["ThermoMoleCore", "ThermoMoleSMC"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ThermoMole",
            dependencies: ["ThermoMoleCore", "ThermoMoleNative"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "ThermoMoleCLI",
            dependencies: ["ThermoMoleCore", "ThermoMoleNative"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ThermoMoleCoreCheck",
            dependencies: ["ThermoMoleCore"]
        ),
        .testTarget(
            name: "ThermoMoleCoreTests",
            dependencies: ["ThermoMoleCore"]
        )
    ]
)
