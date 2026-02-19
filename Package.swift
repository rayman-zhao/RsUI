// swift-tools-version: 5.10

import PackageDescription

let GUILinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS"], .when(configuration: .release)),
    // Update the entry point to point to the generated swift function, this lets us keep the same main method
    // for debug/release
    .unsafeFlags(["-Xlinker", "/ENTRY:mainCRTStartup"], .when(configuration: .release)),
    .unsafeFlags(["-Xlinker", "Samples/Assets/SampleApp.res"]),
]

let package = Package(
    name: "RsUI",
    products: [
        .library(
            name: "RsUI",
            targets: ["RsUI"]
        ),
        .executable(
            name: "SampleApp",
            targets: ["SampleApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/rayman-zhao/swift-cwinrt", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/swift-windowsfoundation", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/swift-uwp", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/swift-windowsappsdk", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/swift-winui", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/swift-cppwinrt", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/RsHelper", branch: "main"),
    ],
    targets: [
        .target(
            name: "RsUI",
            dependencies: [
                .product(name: "CWinRT", package: "swift-cwinrt"),
                .product(name: "WindowsFoundation", package: "swift-windowsfoundation"),
                .product(name: "UWP", package: "swift-uwp"),
                .product(name: "WinAppSDK", package: "swift-windowsappsdk"),
                .product(name: "WinUI", package: "swift-winui"),
                .product(name: "CppWinRT", package: "swift-cppwinrt"),
                .product(name: "RsHelper", package: "RsHelper"),
            ],
        ),
        .executableTarget(
            name: "SampleApp",
            dependencies: [
                "RsUI",
            ],
            path: "Samples",
            resources: [
                .process("Assets")
            ],
            linkerSettings: GUILinkerSettings,
        ),
        .testTarget(
            name: "RsUITests",
            dependencies: [
                "RsUI",
            ]
        ),
    ]
)