//
//  MySQLConnectionPool.swift
//  feather-database-mysql
//
//  Created by Codex on 2026. 06. 04..
//

import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL

actor MySQLConnectionPool {

    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<MySQLConnection, Error>
    }

    private let configuration: MySQLClient.Configuration
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var availableConnections: [MySQLConnection] = []
    private var waiters: [Waiter] = []
    private var totalConnections = 0
    private var nextWaiterID = 0
    private var isShutdown = false
    private var didShutdownEventLoopGroup = false

    init(configuration: MySQLClient.Configuration) {
        self.configuration = configuration
        self.eventLoopGroup = MultiThreadedEventLoopGroup(
            numberOfThreads: configuration.eventLoopThreads
        )
    }

    func warmup() async throws {
        guard !isShutdown else { return }
        let target = configuration.minimumConnections
        guard totalConnections < target else { return }
        let newConnections = target - totalConnections

        for _ in 0..<newConnections {
            let connection = try await makeConnection()
            availableConnections.append(connection)
            totalConnections += 1
        }
    }

    func leaseConnection() async throws -> MySQLConnection {
        guard !isShutdown else {
            throw MySQLConnectionPoolError.shutdown
        }

        if let connection = availableConnections.popLast() {
            return connection
        }

        if totalConnections < configuration.maximumConnections {
            totalConnections += 1
            do {
                return try await makeConnection()
            }
            catch {
                totalConnections -= 1
                throw error
            }
        }

        let waiterID = nextWaiterID
        nextWaiterID += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(
                    Waiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    func releaseConnection(
        _ connection: MySQLConnection
    ) async {
        if isShutdown {
            await closeConnection(connection)
            totalConnections = max(0, totalConnections - 1)
            await shutdownEventLoopGroupIfNeeded()
            return
        }

        if connection.isClosed {
            totalConnections = max(0, totalConnections - 1)
            await closeConnection(connection)

            guard !waiters.isEmpty else {
                return
            }

            let waiter = waiters.removeFirst()

            do {
                let replacement = try await makeConnection()
                totalConnections += 1
                waiter.continuation.resume(returning: replacement)
            }
            catch {
                waiter.continuation.resume(throwing: error)
            }
            return
        }

        if waiters.isEmpty {
            availableConnections.append(connection)
            return
        }

        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: connection)
    }

    func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true

        let connections = availableConnections
        availableConnections.removeAll(keepingCapacity: false)

        for connection in connections {
            await closeConnection(connection)
            totalConnections = max(0, totalConnections - 1)
        }

        for waiter in waiters {
            waiter.continuation.resume(
                throwing: MySQLConnectionPoolError.shutdown
            )
        }
        waiters.removeAll(keepingCapacity: false)

        await shutdownEventLoopGroupIfNeeded()
    }

    func connectionCount() -> Int {
        totalConnections
    }

    private func cancelWaiter(
        id: Int
    ) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func makeConnection() async throws -> MySQLConnection {
        let connection =
            try await MySQLConnection.connect(
                to: try SocketAddress.makeAddressResolvingHost(
                    configuration.host,
                    port: configuration.port
                ),
                username: configuration.username,
                database: configuration.database,
                password: configuration.password,
                tlsConfiguration: configuration.tlsConfiguration,
                serverHostname: configuration.serverHostname,
                logger: configuration.logger,
                on: eventLoopGroup.next()
            )
            .get()

        return connection
    }

    private func closeConnection(
        _ connection: MySQLConnection
    ) async {
        do {
            try await connection.close().get()
        }
        catch {
            configuration.logger.warning(
                "Failed to close MySQL connection",
                metadata: [
                    "error": "\(error)"
                ]
            )
        }
    }

    private func shutdownEventLoopGroupIfNeeded() async {
        guard isShutdown, totalConnections == 0, !didShutdownEventLoopGroup
        else {
            return
        }

        do {
            try await eventLoopGroup.shutdownGracefully()
        }
        catch {
            configuration.logger.warning(
                "Failed to shutdown MySQL event loop group",
                metadata: [
                    "error": "\(error)"
                ]
            )
        }
        didShutdownEventLoopGroup = true
    }
}
