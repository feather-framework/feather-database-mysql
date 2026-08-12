//
//  MySQLClient.swift
//  feather-database-mysql
//
//  Created by Binary Birds on 2026. 06. 04.
//

import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL

/// A MySQL client backed by a lightweight connection pool.
///
/// Use this client to execute queries and transactions concurrently.
public final class MySQLClient: Sendable {

    /// Configuration values for a pooled MySQL client.
    public struct Configuration: Sendable {
        /// The MySQL host name.
        public let host: String
        /// The MySQL port.
        public let port: Int
        /// The MySQL username.
        public let username: String
        /// The MySQL database name.
        public let database: String
        /// The MySQL password.
        public let password: String?
        /// TLS configuration used when opening connections.
        public let tlsConfiguration: TLSConfiguration?
        /// The server host name used for TLS verification.
        public let serverHostname: String?
        /// Minimum number of pooled connections to keep open.
        public let minimumConnections: Int
        /// Maximum number of pooled connections to allow.
        public let maximumConnections: Int
        /// Number of threads used by the pool's event loop group.
        public let eventLoopThreads: Int

        /// Create a pooled MySQL client configuration.
        /// - Parameters:
        ///   - host: The MySQL host name.
        ///   - port: The MySQL port.
        ///   - username: The username used when connecting.
        ///   - database: The database used when connecting.
        ///   - password: The password used when connecting.
        ///   - tlsConfiguration: The TLS configuration to use.
        ///   - serverHostname: The server host name used for TLS verification.
        ///   - minimumConnections: The minimum number of pooled connections.
        ///   - maximumConnections: The maximum number of pooled connections.
        ///   - eventLoopThreads: The number of event loop threads to use.
        public init(
            host: String,
            port: Int,
            username: String,
            database: String,
            password: String? = nil,
            tlsConfiguration: TLSConfiguration? = .makeClientConfiguration(),
            serverHostname: String? = nil,
            minimumConnections: Int = 1,
            maximumConnections: Int = System.coreCount,
            eventLoopThreads: Int = 1
        ) {
            precondition(port > 0)
            precondition(minimumConnections >= 0)
            precondition(maximumConnections >= 1)
            precondition(minimumConnections <= maximumConnections)
            precondition(eventLoopThreads >= 1)

            self.host = host
            self.port = port
            self.username = username
            self.database = database
            self.password = password
            self.tlsConfiguration = tlsConfiguration
            self.serverHostname = serverHostname
            self.minimumConnections = minimumConnections
            self.maximumConnections = maximumConnections
            self.eventLoopThreads = eventLoopThreads
        }
    }

    private let pool: MySQLConnectionPool

    /// Create a MySQL client with a lightweight connection pool.
    /// - Parameter configuration: The client configuration.
    public init(configuration: Configuration) {
        self.pool = MySQLConnectionPool(configuration: configuration)
    }

    // MARK: - pool service

    /// Pre-open the minimum number of connections.
    public func run() async throws {
        try await pool.warmup()
    }

    /// Close all pooled connections and refuse new leases.
    public func shutdown() async {
        await pool.shutdown()
    }

    // MARK: - database api

    /// Execute work using a leased connection.
    ///
    /// The connection is returned to the pool when the closure completes.
    /// - Parameter closure: A closure that receives a MySQL connection.
    /// - Throws: A connection error if leasing or execution fails.
    /// - Returns: The result produced by the closure.
    @discardableResult
    public func withConnection<T>(
        _ closure: (MySQLConnection) async throws -> T
    ) async throws -> T {
        let connection = try await leaseConnection()
        do {
            let result = try await closure(connection)
            await pool.releaseConnection(connection)
            return result
        }
        catch {
            await pool.releaseConnection(connection)
            throw error
        }
    }

    func connectionCount() async -> Int {
        await pool.connectionCount()
    }

    private func leaseConnection() async throws -> MySQLConnection {
        try await pool.leaseConnection()
    }
}
