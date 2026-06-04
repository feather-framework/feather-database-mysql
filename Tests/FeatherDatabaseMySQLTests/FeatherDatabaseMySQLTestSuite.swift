//
//  FeatherDatabaseMySQLTestSuite.swift
//  feather-database-mysql
//
//  Created by Tibor Bödecs on 2026. 01. 10..
//

import FeatherDatabase
import Logging
import MySQLNIOExtras
import NIOSSL
import Testing

@testable import FeatherDatabaseMySQL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct FeatherDatabaseMySQLTestSuite {
    static let sharedLogger: Logger = {
        var logger = Logger(label: "test")
        logger.logLevel = .info
        return logger
    }()

    static let sharedPoolClient: MySQLClient = {
        let environment = ProcessInfo.processInfo.environment
        let finalCertPath =
            environment["MYSQL_CA_CERT_PATH"]
            ?? URL(
                fileURLWithPath: #filePath
            )
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docker")
            .appendingPathComponent("mariadb")
            .appendingPathComponent("certificates")
            .appendingPathComponent("ca.pem")
            .path()

        let host = environment["MYSQL_HOST"] ?? "localhost"
        let port = environment["MYSQL_PORT"].flatMap(Int.init) ?? 3306
        let password = environment["MYSQL_PASSWORD"] ?? "mariadb"

        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        let rootCert = try! NIOSSLCertificate.fromPEMFile(finalCertPath)
        tlsConfig.trustRoots = .certificates(rootCert)
        tlsConfig.certificateVerification = .fullVerification

        return MySQLClient(
            configuration: .init(
                host: host,
                port: port,
                username: "root",
                database: environment["MYSQL_DATABASE"] ?? "mariadb",
                password: password,
                tlsConfiguration: tlsConfig,
                serverHostname: host,
                logger: sharedLogger,
                minimumConnections: 0,
                maximumConnections: 4,
                eventLoopThreads: 1
            )
        )
    }()
    func randomTableSuffix() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var suffix = ""
        suffix.reserveCapacity(16)
        for _ in 0..<16 {
            suffix.append(characters.randomElement() ?? "a")
        }
        return suffix
    }

    func runUsingTestDatabaseClient(
        _ closure: ((DatabaseClientMySQL) async throws -> Void)
    ) async throws {
        let logger = Self.sharedLogger
        let client = Self.sharedPoolClient

        do {
            let database = DatabaseClientMySQL(
                client: client,
                logger: logger
            )

            try await closure(database)
        }
        catch {
            Issue.record(error)
        }
    }

    // MARK: -

    @Test
    func foreignKeySupport() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let planetsTable = "planets_\(suffix)"
            let moonsTable = "moons_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: moonsTable)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: planetsTable)`;
                        """#
                )

                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: planetsTable)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT NOT NULL
                        ) ENGINE=InnoDB;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: moonsTable)` (
                            `id` INTEGER PRIMARY KEY,
                            `planet_id` INTEGER NOT NULL,
                            CONSTRAINT `fk_\#(unescaped: moonsTable)`
                                FOREIGN KEY (`planet_id`)
                                REFERENCES `\#(unescaped: planetsTable)` (`id`)
                        ) ENGINE=InnoDB;
                        """#
                )

                do {
                    _ = try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: moonsTable)`
                                (`id`, `planet_id`)
                            VALUES
                                (1, 999);
                            """#
                    )
                    Issue.record("Expected foreign key constraint violation.")
                }
                catch DatabaseError.query(let error) {
                    #expect(
                        "\(error)".contains("foreign key constraint fails")
                    )
                }
                catch {
                    Issue.record("Expected database query error to be thrown.")
                }
            }
        }
    }

    @Test
    func tableCreation() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "galaxies_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )

                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                let results = try await connection.run(
                    query: #"""
                        SELECT `table_name`
                        FROM `information_schema`.`tables`
                        WHERE `table_schema` = DATABASE()
                            AND `table_name` = '\#(unescaped: table)'
                        ORDER BY `table_name`;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 1)

                let item = results[0]
                let name = try item.decode(
                    column: "table_name",
                    as: String.self
                )
                #expect(name == table)
            }
        }
    }

    @Test
    func tableInsert() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "galaxies_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                let name1 = "Andromeda"
                let name2 = "Milky Way"

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `name`)
                        VALUES
                            (\#(1), \#(name1)),
                            (\#(2), \#(name2));
                        """#
                )

                let results = try await connection.run(
                    query: #"""
                        SELECT * FROM `\#(unescaped: table)` ORDER BY `name` ASC;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 2)

                let item1 = results[0]
                let name1result = try item1.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name1result == name1)

                let item2 = results[1]
                let name2result = try item2.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name2result == name2)
            }
        }
    }

    @Test
    func rowDecoding() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "foo_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc'),
                            (2, NULL);
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`, `value`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "id", as: Int?.self) == .some(1)
                )
                #expect(
                    (try? item1.decode(column: "value", as: Int?.self)) == nil
                )

                #expect(
                    try item1.decode(column: "value", as: String.self) == "abc"
                )
                #expect(
                    (try? item2.decode(column: "value", as: String.self)) == nil
                )

                #expect(
                    (try item1.decode(column: "value", as: String?.self))
                        == .some("abc")
                )
                #expect(
                    (try item2.decode(column: "value", as: String?.self))
                        == .none
                )
            }
        }
    }

    @Test
    func queryEncoding() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "foo_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )

                let row1: (Int, String?) = (1, "abc")
                let row2: (Int, String?) = (2, nil)

                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (\#(row1.0), \#(row1.1)),
                            (\#(row2.0), \#(row2.1));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`, `value`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id` ASC;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "value", as: String?.self) == "abc"
                )
                #expect(
                    try item2.decode(column: "value", as: String?.self) == nil
                )
            }
        }
    }

    @Test
    func unsafeSQLBindings() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "widgets_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `name`)
                        VALUES
                            (\#(1), \#("gizmo"));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "gizmo"
                )
            }
        }
    }

    @Test
    func optionalStringInterpolationNil() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "notes_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `body` TEXT
                        );
                        """#
                )

                let body: String? = nil

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `body`)
                        VALUES
                            (1, \#(body));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `body`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "body", as: String?.self)
                        == nil
                )
            }
        }
    }

    @Test
    func mysqlDataInterpolation() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "tags_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `label` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `label`)
                        VALUES
                            (1, \#("alpha"));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `label`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "label", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func boundOptionalInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let boundString: String? = "alpha"
                let missingString: String? = nil
                let boundInt: Int? = 21
                let missingInt: Int? = nil
                let boundFloat: Float? = 1.25
                let missingFloat: Float? = nil
                let boundDouble: Double? = 3.75
                let missingDouble: Double? = nil
                let boundBool: Bool? = true
                let missingBool: Bool? = nil

                struct OptionalRow: Sendable {
                    let boundString: String?
                    let missingString: String?
                    let boundInt: Int?
                    let missingInt: Int?
                    let boundFloat: Double?
                    let missingFloat: Double?
                    let boundDouble: Double?
                    let missingDouble: Double?
                    let boundBool: Int?
                    let missingBool: Int?

                    init(_ row: DatabaseRow) throws {
                        self.boundString = try row.decode(
                            column: "bound_string",
                            as: String?.self
                        )
                        self.missingString = try row.decode(
                            column: "missing_string",
                            as: String?.self
                        )
                        self.boundInt = try row.decode(
                            column: "bound_int",
                            as: Int?.self
                        )
                        self.missingInt = try row.decode(
                            column: "missing_int",
                            as: Int?.self
                        )
                        self.boundFloat = try row.decode(
                            column: "bound_float",
                            as: Double?.self
                        )
                        self.missingFloat = try row.decode(
                            column: "missing_float",
                            as: Double?.self
                        )
                        self.boundDouble = try row.decode(
                            column: "bound_double",
                            as: Double?.self
                        )
                        self.missingDouble = try row.decode(
                            column: "missing_double",
                            as: Double?.self
                        )
                        self.boundBool = try row.decode(
                            column: "bound_bool",
                            as: Int?.self
                        )
                        self.missingBool = try row.decode(
                            column: "missing_bool",
                            as: Int?.self
                        )
                    }
                }

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            \#(boundString) AS `bound_string`,
                            \#(missingString) AS `missing_string`,
                            \#(boundInt) AS `bound_int`,
                            \#(missingInt) AS `missing_int`,
                            \#(boundFloat) AS `bound_float`,
                            \#(missingFloat) AS `missing_float`,
                            \#(boundDouble) AS `bound_double`,
                            \#(missingDouble) AS `missing_double`,
                            \#(boundBool) AS `bound_bool`,
                            \#(missingBool) AS `missing_bool`;
                        """#
                ) { try await $0.collect().map { try OptionalRow($0) } }

                #expect(result.count == 1)
                #expect(result[0].boundString == "alpha")
                #expect(result[0].missingString == nil)
                #expect(result[0].boundInt == 21)
                #expect(result[0].missingInt == nil)
                #expect(result[0].boundFloat == 1.25)
                #expect(result[0].missingFloat == nil)
                #expect(result[0].boundDouble == 3.75)
                #expect(result[0].missingDouble == nil)
                #expect(result[0].boundBool == 1)
                #expect(result[0].missingBool == nil)
            }
        }
    }

    @Test
    func unescapedOptionalInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let rawString: String? = "beta"
                let missingString: String? = nil
                let rawInt: Int? = 7
                let missingInt: Int? = nil
                let rawFloat: Float? = 2.5
                let missingFloat: Float? = nil
                let rawDouble: Double? = 4.5
                let missingDouble: Double? = nil
                let rawBool: Bool? = false
                let missingBool: Bool? = nil

                struct RawOptionalRow: Sendable {
                    let rawString: String?
                    let missingString: String?
                    let rawInt: Int?
                    let missingInt: Int?
                    let rawFloat: Double?
                    let missingFloat: Double?
                    let rawDouble: Double?
                    let missingDouble: Double?
                    let rawBool: Int?
                    let missingBool: Int?

                    init(_ row: DatabaseRow) throws {
                        self.rawString = try row.decode(
                            column: "raw_string",
                            as: String?.self
                        )
                        self.missingString = try row.decode(
                            column: "missing_string",
                            as: String?.self
                        )
                        self.rawInt = try row.decode(
                            column: "raw_int",
                            as: Int?.self
                        )
                        self.missingInt = try row.decode(
                            column: "missing_int",
                            as: Int?.self
                        )
                        self.rawFloat = try row.decode(
                            column: "raw_float",
                            as: Double?.self
                        )
                        self.missingFloat = try row.decode(
                            column: "missing_float",
                            as: Double?.self
                        )
                        self.rawDouble = try row.decode(
                            column: "raw_double",
                            as: Double?.self
                        )
                        self.missingDouble = try row.decode(
                            column: "missing_double",
                            as: Double?.self
                        )
                        self.rawBool = try row.decode(
                            column: "raw_bool",
                            as: Int?.self
                        )
                        self.missingBool = try row.decode(
                            column: "missing_bool",
                            as: Int?.self
                        )
                    }
                }

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            '\#(unescaped: rawString)' AS `raw_string`,
                            \#(unescaped: missingString) AS `missing_string`,
                            \#(unescaped: rawInt) AS `raw_int`,
                            \#(unescaped: missingInt) AS `missing_int`,
                            \#(unescaped: rawFloat) AS `raw_float`,
                            \#(unescaped: missingFloat) AS `missing_float`,
                            \#(unescaped: rawDouble) AS `raw_double`,
                            \#(unescaped: missingDouble) AS `missing_double`,
                            \#(unescaped: rawBool) AS `raw_bool`,
                            \#(unescaped: missingBool) AS `missing_bool`;
                        """#
                ) { try await $0.collect().map { try RawOptionalRow($0) } }

                #expect(result.count == 1)
                #expect(result[0].rawString == "beta")
                #expect(result[0].missingString == nil)
                #expect(result[0].rawInt == 7)
                #expect(result[0].missingInt == nil)
                #expect(result[0].rawFloat == 2.5)
                #expect(result[0].missingFloat == nil)
                #expect(result[0].rawDouble == 4.5)
                #expect(result[0].missingDouble == nil)
                #expect(result[0].rawBool == 0)
                #expect(result[0].missingBool == nil)
            }
        }
    }

    @Test
    func arrayInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "array_samples_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL,
                            `ratio` DOUBLE NOT NULL,
                            `score` DOUBLE NOT NULL,
                            `active` BOOLEAN NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `name`, `ratio`, `score`, `active`)
                        VALUES
                            (1, 'alpha', 1.5, 3.5, true),
                            (2, 'beta', 2.25, 4.75, false);
                        """#
                )

                let names = ["alpha", "omega"]
                let ids = [1, 99]
                let ratios: [Float] = [1.5, 9.5]
                let scores = [3.5, 9.75]
                let flags = [true, false]

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        WHERE
                            `name` IN (\#(names))
                            AND `id` IN (\#(ids))
                            AND `ratio` IN (\#(ratios))
                            AND `score` IN (\#(scores))
                            AND `active` IN (\#(flags))
                        ORDER BY `id`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(try result[0].decode(column: "id", as: Int.self) == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func optionalArrayInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "optional_array_samples_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL,
                            `ratio` DOUBLE NOT NULL,
                            `score` DOUBLE NOT NULL,
                            `active` BOOLEAN NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `name`, `ratio`, `score`, `active`)
                        VALUES
                            (1, 'alpha', 1.5, 3.5, true),
                            (2, 'beta', 2.25, 4.75, false);
                        """#
                )

                let names: [String?] = ["alpha", nil, "omega"]
                let ids: [Int?] = [1, nil, 99]
                let ratios: [Float?] = [1.5, nil, 9.5]
                let scores: [Double?] = [3.5, nil, 9.75]
                let flags: [Bool?] = [true, nil, false]

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        WHERE
                            `name` IN (\#(names))
                            AND `id` IN (\#(ids))
                            AND `ratio` IN (\#(ratios))
                            AND `score` IN (\#(scores))
                            AND `active` IN (\#(flags))
                        ORDER BY `id`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(try result[0].decode(column: "id", as: Int.self) == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func booleanInterpolation() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT
                            \#(true) AS `enabled`,
                            \#(false) AS `disabled`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "enabled", as: Int.self) == 1
                )
                #expect(
                    try result[0].decode(column: "disabled", as: Int.self) == 0
                )
            }
        }
    }

    @Test
    func booleanInterpolationInWhereClause() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "flags_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `is_enabled` INTEGER NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `is_enabled`)
                        VALUES
                            (1, 1),
                            (2, 0);
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT COUNT(*) AS `count`
                        FROM `\#(unescaped: table)`
                        WHERE `is_enabled` = \#(true);
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "count", as: Int.self) == 1
                )
            }
        }
    }

    @Test
    func resultSequenceIterator() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "numbers_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'one'),
                            (2, 'two');
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT `id`, `value`
                        FROM `\#(unescaped: table)`
                        ORDER BY `id`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 2)

                let first = result[0]
                let second = result[1]

                #expect(try first.decode(column: "id", as: Int.self) == 1)
                #expect(
                    try first.decode(column: "value", as: String.self) == "one"
                )

                #expect(try second.decode(column: "id", as: Int.self) == 2)
                #expect(
                    try second.decode(column: "value", as: String.self) == "two"
                )
            }
        }
    }

    @Test
    func collectFirstReturnsFirstRow() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "widgets_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`name`)
                        VALUES
                            ('alpha'),
                            ('beta');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            ORDER BY `id` ASC;
                            """#
                    ) { try await $0.collect() }
                    .first

                #expect(
                    try result?.decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func transactionSuccess() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )

                try await database.withTransaction { connection in
                    try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (1, 'widget');
                            """#
                    )
                }

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `name`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "widget"
                )
            }
        }
    }

    @Test
    func transactionFailurePropagates() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "dummy_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `name` TEXT NOT NULL
                        );
                        """#
                )
            }

            do {
                try await database.withTransaction { connection in
                    try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (1, 'ok');
                            """#
                    )

                    return try await connection.run(
                        query: #"""
                            INSERT INTO `\#(unescaped: table)`
                                (`id`, `name`)
                            VALUES
                                (2, NULL);
                            """#
                    )
                }
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }
            catch DatabaseError.transaction(let error) {
                #expect(error.beginError == nil)
                #expect(error.closureError != nil)
                #expect(
                    error.closureError.debugDescription.contains(
                        "cannot be null"
                    )
                )
                #expect(error.rollbackError == nil)
                #expect(error.commitError == nil)
            }
            catch {
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }

            try await database.withConnection { connection in
                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.isEmpty)
            }
        }
    }

    @Test
    func transactionClosureErrorPropagates() async throws {
        try await runUsingTestDatabaseClient { database in
            enum TestError: Error, Equatable {
                case boom
            }

            do {
                _ = try await database.withTransaction { _ in
                    throw TestError.boom
                }
                Issue.record("Expected transaction error to be thrown.")
            }
            catch DatabaseError.transaction(let error) {
                #expect(error.beginError == nil)
                #expect(error.commitError == nil)
                #expect(error.rollbackError == nil)
                #expect((error.closureError as? TestError) == .boom)
                #expect(error.file.isEmpty == false)
                #expect(error.line > 0)
            }
            catch {
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }
        }
    }

    @Test
    func doubleRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "measurements_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` DOUBLE NOT NULL
                        );
                        """#
                )

                let expected = 1.5

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, \#(expected));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `value`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "value", as: Double.self)
                        == expected
                )
            }
        }
    }

    @Test
    func missingColumnThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `id`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: String.self)
                    Issue.record("Expected decoding a missing column to throw.")
                }
                catch DecodingError.dataCorrupted {

                }
                catch {
                    Issue.record(
                        "Expected a dataCorrupted error for missing column."
                    )
                }
            }
        }
    }

    @Test
    func typeMismatchThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "items_\(suffix)"

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT `value`
                            FROM `\#(unescaped: table)`;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: Int.self)
                    Issue.record("Expected decoding a string as Int to throw.")
                }
                catch DecodingError.typeMismatch {

                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error when decoding a string as Int."
                    )
                }
            }
        }
    }

    @Test
    func nullDecodingThrowsTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "nullable_values_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` INTEGER
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, NULL);
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT `value`
                        FROM `\#(unescaped: table)`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: Int.self)
                    Issue.record("Expected decoding NULL as Int to throw.")
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains("Could not convert")
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error when decoding NULL as Int."
                    )
                }
            }
        }
    }

    @Test
    func nonSQLiteDecodableTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct CustomValue: Decodable, Sendable {
                let value: String
            }

            let suffix = randomTableSuffix()
            let table = "custom_types_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` INTEGER NOT NULL PRIMARY KEY,
                            `value` TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `value`)
                        VALUES
                            (1, 'alpha');
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT `value`
                        FROM `\#(unescaped: table)`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: CustomValue.self
                        )
                    Issue.record(
                        "Expected decoding non-MySQLDecodable type to throw."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Keyed decoding is not supported."
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for non-MySQLDecodable types."
                    )
                }
            }
        }
    }

    @Test
    func singleValueDecodingTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct CustomValue: Decodable, Sendable {
                let value: String
            }

            struct Wrapper: Decodable, Sendable {
                let value: CustomValue

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    value = try container.decode(CustomValue.self)
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'abc' AS `value`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: Wrapper.self
                        )
                    Issue.record(
                        "Expected single-value decoding to throw typeMismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Data is not convertible"
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for single-value decoding."
                    )
                }
            }
        }
    }

    @Test
    func nonDecodingErrorThrownFromDecodeIsMapped() async throws {
        try await runUsingTestDatabaseClient { database in
            enum TestError: Error {
                case boom
            }

            struct ThrowingValue: Decodable, Sendable {
                init(from _: Decoder) throws {
                    throw TestError.boom
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'abc' AS `value`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: ThrowingValue.self
                        )
                    Issue.record(
                        "Expected non-DecodingError to map to typeMismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Data is not convertible"
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected typeMismatch when decoding throws non-DecodingError."
                    )
                }
            }
        }
    }

    @Test
    func unkeyedRowDecodingThrowsTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct UnkeyedValue: Decodable, Sendable {
                init(from decoder: Decoder) throws {
                    var container = try decoder.unkeyedContainer()
                    _ = try container.decode(String.self)
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'value' AS `value`;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: UnkeyedValue.self
                        )
                    Issue.record(
                        "Expected unkeyed decoding to throw a type mismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Unkeyed decoding is not supported."
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for unkeyed decoding."
                    )
                }
            }
        }
    }

    @Test
    func queryFailureErrorText() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "missing_table_\(suffix)"

            try await database.withConnection { connection in
                do {
                    _ = try await connection.run(
                        query: #"""
                            SELECT *
                            FROM `\#(unescaped: table)`;
                            """#
                    )
                    Issue.record("Expected query to fail for missing table.")
                }
                catch DatabaseError.query(let error) {
                    #expect("\(error)".contains("doesn't exist"))
                }
                catch {
                    Issue.record("Expected database query error to be thrown.")
                }
            }
        }
    }

    @Test
    func versionCheck() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT
                            VERSION() AS `version`
                        WHERE
                            1=\#(1);
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let version = try item.decode(
                    column: "version",
                    as: String.self
                )
                #expect(!version.isEmpty)
            }
        }
    }

    @Test
    func sslCheckStatus() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SHOW VARIABLES LIKE 'have_ssl';
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let name = try item.decode(
                    column: "Variable_name",
                    as: String.self
                )
                #expect(name == "have_ssl")

                let value = try item.decode(column: "Value", as: String.self)
                #expect(value == "YES")
            }
        }
    }

    @Test
    func sslCheckCypher() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SHOW SESSION STATUS LIKE "ssl_cipher";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let name = try item.decode(
                    column: "Variable_name",
                    as: String.self
                )
                #expect(name == "Ssl_cipher")

                let value = try item.decode(column: "Value", as: String.self)
                #expect(value == "TLS_AES_128_GCM_SHA256")
            }
        }
    }

    @Test
    func concurrentTransactionUpdates() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "sessions_\(suffix)"
            let sessionID = "session_\(suffix)"

            enum TestError: Error {
                case missingRow
            }

            try await database.withConnection { connection in

                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE `\#(unescaped: table)` (
                            `id` VARCHAR(255) NOT NULL PRIMARY KEY,
                            `access_token` TEXT NOT NULL,
                            `access_expires_at` TIMESTAMP NOT NULL,
                            `refresh_token` TEXT NOT NULL,
                            `refresh_count` INTEGER NOT NULL DEFAULT 0
                        );
                        """#
                )

                // set an expired token
                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)`
                            (`id`, `access_token`, `access_expires_at`, `refresh_token`, `refresh_count`)
                        VALUES
                            (
                                \#(sessionID),
                                'stale',
                                NOW() - INTERVAL 5 MINUTE,
                                'refresh',
                                0
                            );
                        """#
                )
            }

            func getValidAccessToken(sessionID: String) async throws -> String {
                try await database.withTransaction { connection in
                    let result = try await connection.run(
                        query: #"""
                            SELECT
                                `access_token`,
                                `refresh_count`,
                                `access_expires_at` > NOW() + INTERVAL 60 SECOND AS `is_valid`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = \#(sessionID)
                            FOR UPDATE;
                            """#
                    ) { try await $0.collect() }

                    guard let row = result.first else {
                        throw TestError.missingRow
                    }

                    let isValid = try row.decode(
                        column: "is_valid",
                        as: Bool.self
                    )
                    if isValid {
                        // token was valid, must be called X times
                        return try row.decode(
                            column: "access_token",
                            as: String.self
                        )
                    }

                    // refresh, this branch can only be called 1 time
                    let refreshCount = try row.decode(
                        column: "refresh_count",
                        as: Int.self
                    )
                    let newRefreshCount = refreshCount + 1
                    let newToken = "token_\(newRefreshCount)"

                    try await Task.sleep(for: .milliseconds(40))

                    try await connection.run(
                        query: #"""
                            UPDATE `\#(unescaped: table)`
                            SET
                                `access_token` = \#(newToken),
                                `access_expires_at` = NOW() + INTERVAL 10 MINUTE,
                                `refresh_count` = \#(newRefreshCount)
                            WHERE `id` = \#(sessionID);
                            """#
                    )

                    return newToken
                }
            }

            let workerCount = 80
            var tokens: [String] = []
            try await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        try await getValidAccessToken(sessionID: sessionID)
                    }
                }
                for try await token in group {
                    tokens.append(token)
                }
            }

            #expect(Set(tokens).count == 1)

            try await database.withConnection { connection in

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT
                                `access_token`,
                                `refresh_count`,
                                `access_expires_at` > NOW() AS `is_valid`
                            FROM `\#(unescaped: table)`
                            WHERE `id` = \#(sessionID);
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "refresh_count", as: Int.self)
                        == 1
                )
                #expect(
                    try result[0]
                        .decode(column: "access_token", as: String.self)
                        == "token_1"
                )
                #expect(
                    try result[0].decode(column: "is_valid", as: Bool.self)
                        == true
                )
            }
        }
    }

    // MARK: - sequence tests

    @Test
    func rowSequenceIteratesRowsInOrder() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "planets_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)` (`id`, `name`)
                        VALUES
                            (1, 'Mercury'),
                            (2, 'Venus');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT *
                        FROM `\#(unescaped: table)`
                        ORDER BY `id` ASC;
                        """#
                )

                var iterator = sequence.makeAsyncIterator()

                let first = await iterator.next()
                #expect(first != nil)
                #expect(
                    try first?.decode(column: "name", as: String.self)
                        == "Mercury"
                )

                let second = await iterator.next()
                #expect(second != nil)
                #expect(
                    try second?.decode(column: "name", as: String.self)
                        == "Venus"
                )

                let third = await iterator.next()
                #expect(third == nil)
            }
        }
    }

    @Test
    func rowSequenceCollectReturnsAllRows() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "greetings_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO `\#(unescaped: table)` (`id`, `name`)
                        VALUES
                            (1, 'Hello'),
                            (2, 'World');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        ORDER BY `id` ASC;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.count == 2)

                let firstName = try rows[0]
                    .decode(
                        column: "name",
                        as: String.self
                    )
                let secondName = try rows[1]
                    .decode(
                        column: "name",
                        as: String.self
                    )

                #expect(firstName == "Hello")
                #expect(secondName == "World")
            }
        }
    }

    @Test
    func rowSequenceHandlesEmptyResults() async throws {
        try await runUsingTestDatabaseClient { database in
            let suffix = randomTableSuffix()
            let table = "empty_rows_\(suffix)"

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        DROP TABLE IF EXISTS `\#(unescaped: table)`;
                        """#
                )
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS `\#(unescaped: table)` (
                            `id` INTEGER PRIMARY KEY,
                            `name` TEXT
                        );
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            `id`,
                            `name`
                        FROM `\#(unescaped: table)`
                        WHERE
                            1=0;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.isEmpty)

                var iterator = sequence.makeAsyncIterator()
                let first = await iterator.next()
                #expect(first == nil)
            }
        }
    }

}
