// swift-tools-version:6.1
import PackageDescription

// NOTE: https://github.com/swift-server/swift-http-server/blob/main/Package.swift
var defaultSwiftSettings: [SwiftSetting] =
[
    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0441-formalize-language-mode-terminology.md
    .swiftLanguageMode(.v6),
    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),
    // https://forums.swift.org/t/experimental-support-for-lifetime-dependencies-in-swift-6-2-and-beyond/78638
    .enableExperimentalFeature("Lifetimes"),
    // https://github.com/swiftlang/swift/pull/65218
    .enableExperimentalFeature("AvailabilityMacro=FeatherDatabaseMySQL 1.0:macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0"),
]

#if compiler(>=6.2)
defaultSwiftSettings.append(
    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
)
#endif


let package = Package(
    name: "feather-database-mysql",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "MySQLNIOExtras", targets: ["MySQLNIOExtras"]),
        .library(name: "FeatherDatabaseMySQL", targets: ["FeatherDatabaseMySQL"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/vapor/mysql-nio", from: "1.8.0"),
        .package(url: "https://github.com/feather-framework/feather-database", exact: "1.0.0-rc.2"),
        // [docc-plugin-placeholder]
    ],
    targets: [
        .target(
            name: "MySQLNIOExtras",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .target(
            name: "FeatherDatabaseMySQL",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "FeatherDatabase", package: "feather-database"),
                .target(name: "MySQLNIOExtras"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .testTarget(
            name: "MySQLNIOExtrasTests",
            dependencies: [
                .target(name: "MySQLNIOExtras"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
        .testTarget(
            name: "FeatherDatabaseMySQLTests",
            dependencies: [
                .target(name: "FeatherDatabaseMySQL"),
            ],
            swiftSettings: defaultSwiftSettings
        ),
    ]
)
