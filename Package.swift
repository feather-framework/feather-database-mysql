// swift-tools-version:6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("StrictConcurrency"),
    .enableExperimentalFeature("SuppressedAssociatedTypes"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
]


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
        .package(url: "https://github.com/apple/swift-log", from: "1.16.1"),
        .package(url: "https://github.com/vapor/mysql-nio", from: "1.9.1"),
        .package(
            url: "https://github.com/feather-framework/feather-database",
            exact: "1.0.0-rc.3"
        ),
    ],
    targets: [
        .target(
            name: "MySQLNIOExtras",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "FeatherDatabaseMySQL",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "FeatherDatabase", package: "feather-database"),
                .target(name: "MySQLNIOExtras"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MySQLNIOExtrasTests",
            dependencies: [
                .target(name: "MySQLNIOExtras"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FeatherDatabaseMySQLTests",
            dependencies: [
                .target(name: "FeatherDatabaseMySQL"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
