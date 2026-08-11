//
//  MySQLNIOExtrasTestSuite.swift
//  feather-database-mysql
//
//  Created by Binary Birds on 2026. 06. 05.
//

import Logging
import MySQLNIO
import NIOCore
import NIOSSL
import Testing

@testable import MySQLNIOExtras

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct MySQLNIOExtrasTestSuite {

    actor Latch {
        private var isSignaled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isSignaled {
                return
            }

            await withCheckedContinuation { continuation in
                if isSignaled {
                    continuation.resume()
                    return
                }

                waiters.append(continuation)
            }
        }

        func signal() {
            guard !isSignaled else {
                return
            }

            isSignaled = true
            let pendingWaiters = waiters
            waiters.removeAll(keepingCapacity: false)
            for waiter in pendingWaiters {
                waiter.resume()
            }
        }
    }

    actor Flag {
        private var value = false

        func set() {
            value = true
        }

        func get() -> Bool {
            value
        }
    }

    static func loadRootCertificates(at path: String) -> [NIOSSLCertificate] {
        do {
            return try NIOSSLCertificate.fromPEMFile(path)
        }
        catch {
            fatalError(
                "Failed to load MySQL CA certificate at \(path): \(error)"
            )
        }
    }

    static func makeClient(
        maximumConnections: Int
    ) -> MySQLClient {
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
        tlsConfig.trustRoots = .certificates(
            loadRootCertificates(at: finalCertPath)
        )
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
                minimumConnections: 0,
                maximumConnections: maximumConnections,
                eventLoopThreads: 1
            )
        )
    }

    func withClient<T>(
        maximumConnections: Int = 1,
        _ closure: (MySQLClient) async throws -> T
    ) async throws -> T {
        let client = Self.makeClient(maximumConnections: maximumConnections)
        let logger = Logger(label: "mysql-test")

        return try await withLogger(logger) { _ in
            try await client.run()
            do {
                let result = try await closure(client)
                await client.shutdown()
                return result
            }
            catch {
                await client.shutdown()
                throw error
            }
        }
    }

    @Test
    func closedConnectionIsReplacedForWaitingCaller() async throws {
        try await withClient { client in
            let firstAcquired = Latch()
            let allowFirstToFinish = Latch()

            let first = Task {
                try await client.withConnection { connection in
                    await firstAcquired.signal()
                    await allowFirstToFinish.wait()
                    try await connection.close().get()
                }
            }

            await firstAcquired.wait()

            let second = Task {
                try await client.withConnection { connection in
                    _ = try await connection.query("SELECT 1;", []).get()
                }
            }

            await allowFirstToFinish.signal()
            try await first.value
            try await second.value

            #expect(await client.connectionCount() == 1)
        }
    }

    @Test
    func cancelledWaiterDoesNotBlockQueue() async throws {
        try await withClient { client in
            let firstAcquired = Latch()
            let allowFirstToFinish = Latch()
            let secondStarted = Latch()
            let didRunSecondClosure = Flag()

            let first = Task {
                try await client.withConnection { connection in
                    await firstAcquired.signal()
                    await allowFirstToFinish.wait()
                    _ = try await connection.query("SELECT 1;", []).get()
                }
            }

            await firstAcquired.wait()

            let second = Task {
                await secondStarted.signal()
                return try await client.withConnection { _ in
                    await didRunSecondClosure.set()
                }
            }

            await secondStarted.wait()
            try await Task.sleep(for: .milliseconds(50))
            second.cancel()

            await allowFirstToFinish.signal()
            try await first.value

            do {
                try await second.value
                Issue.record("Expected the waiting task to be cancelled.")
            }
            catch is CancellationError {
                // Expected.
            }
            catch {
                Issue.record("Expected cancellation, got \(error).")
            }

            #expect(await didRunSecondClosure.get() == false)

            try await client.withConnection { connection in
                _ = try await connection.query("SELECT 1;", []).get()
            }

            #expect(await client.connectionCount() == 1)
        }
    }
}
