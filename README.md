# Feather Database MySQL

MySQL/MariaDB driver implementation for the abstract [Feather Database](https://github.com/feather-framework/feather-database) Swift API package.

[
    ![Release: 1.0.0-rc.1](https://img.shields.io/badge/Release-1%2E0%2E0--rc%2E1-F05138)
](
    https://github.com/feather-framework/feather-database-mysql/releases/tag/1.0.0-rc.1
)

## Features

- MySQL/MariaDB driver for Feather Database
- Automatic query parameter escaping via Swift string interpolation.
- Async sequence query results with `Decodable` row support.
- Designed for modern Swift concurrency
- DocC-based API Documentation
- Unit tests and code coverage

## Requirements

![Swift 6.1+](https://img.shields.io/badge/Swift-6%2E1%2B-F05138)
![Platforms: Linux, macOS, iOS, tvOS, watchOS, visionOS](https://img.shields.io/badge/Platforms-Linux_%7C_macOS_%7C_iOS_%7C_tvOS_%7C_watchOS_%7C_visionOS-F05138)

- Swift 6.1+
- Platforms:
  - Linux
  - macOS 15+
  - iOS 18+
  - tvOS 18+
  - watchOS 11+
  - visionOS 2+

## Installation

Add the dependency to your `Package.swift`:

```swift
.package(url: "https://github.com/feather-framework/feather-database-mysql", exact: "1.0.0-rc.1"),
```

Then add `FeatherDatabaseMySQL` to your target dependencies:

```swift
.product(name: "FeatherDatabaseMySQL", package: "feather-database-mysql"),
```

## Usage

API documentation is available at the link below:

[
    ![DocC API documentation](https://img.shields.io/badge/DocC-API_documentation-F05138)
](
    https://feather-framework.github.io/feather-database-mysql/
)

Here is a brief example:

```swift
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL
import FeatherDatabase
import FeatherDatabaseMySQL

var logger = Logger(label: "example")
logger.logLevel = .info

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

let finalCertPath = URL(fileURLWithPath: "path/to/ca.pem")
var tlsConfig = TLSConfiguration.makeClientConfiguration()
let rootCert = try NIOSSLCertificate.fromPEMFile(finalCertPath)
tlsConfig.trustRoots = .certificates(rootCert)
tlsConfig.certificateVerification = .fullVerification

let connection =
    try await MySQLConnection.connect(
        to: try SocketAddress(ipAddress: "127.0.0.1", port: 3306),
        username: "mariadb",
        database: "mariadb",
        password: "mariadb",
        tlsConfiguration: tlsConfig,
        logger: logger,
        on: eventLoopGroup.next()
    )
    .get()

let database = DatabaseClientMySQL(
    connection: connection,
    logger: logger
)

do {
    let result = try await database.withConnection { connection in
        try await connection.run(
            query: #"""
                SELECT
                    VERSION() AS `version`
                WHERE
                    1=\#(1);
                """#
        )
    }
    
    for try await item in result {
        let version = try item.decode(column: "version", as: String.self)
        print(version)
    }

    try await connection.close().get()
    try await eventLoopGroup.shutdownGracefully()
}
catch {
    try await connection.close().get()
    try await eventLoopGroup.shutdownGracefully()

    throw error
}
```

## Other database drivers

The following database client implementations are also available for use:

- [SQLite](https://github.com/feather-framework/feather-database-sqlite)
- [Postgres](https://github.com/feather-framework/feather-database-postgres)

## Development

- Build: `swift build`
- Test:
  - local: `swift test`
  - using Docker: `make docker-test`
- Format: `make format`
- Check: `make check`

## Contributing

[Pull requests](https://github.com/feather-framework/feather-database-mysql/pulls) are welcome. Please keep changes focused and include tests for new logic. 🙏
