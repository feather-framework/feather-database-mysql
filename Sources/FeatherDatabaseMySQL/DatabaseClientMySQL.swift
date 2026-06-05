//
//  DatabaseClientMySQL.swift
//  feather-database-mysql
//
//  Created by Tibor Bödecs on 2026. 01. 10.
//

import FeatherDatabase
import Logging
import MySQLNIO
import MySQLNIOExtras

/// A MySQL-backed database client.
///
/// Use this client to execute queries and manage transactions on MySQL.
public struct DatabaseClientMySQL: DatabaseClient {

    public typealias Connection = DatabaseConnectionMySQL

    private enum Storage {
        case connection(DatabaseConnectionMySQL)
        case client(MySQLClient)
    }

    private let storage: Storage
    private let logger: Logger

    /// Create a MySQL database client.
    ///
    /// Use this initializer to provide an already-open connection.
    /// - Parameters:
    ///   - connection: The MySQL connection to use.
    ///   - logger: The logger for database operations.
    public init(
        connection: MySQLConnection,
        logger: Logger
    ) {
        self.storage = .connection(
            .init(
                connection: connection,
                logger: logger
            )
        )
        self.logger = logger
    }

    /// Create a MySQL database client backed by a connection pool.
    ///
    /// - Parameters:
    ///   - client: The pooled MySQL client to use.
    ///   - logger: The logger for database operations.
    public init(
        client: MySQLClient,
        logger: Logger
    ) {
        self.storage = .client(client)
        self.logger = logger
    }

    // MARK: - database api

    /// Execute work using the stored connection or pooled client.
    ///
    /// The closure is executed with the current connection.
    /// - Parameter closure: A closure that receives the MySQL connection.
    /// - Throws: A `DatabaseError` if the connection fails.
    /// - Returns: The query result produced by the closure.
    @discardableResult
    public func withConnection<T>(
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {
        switch storage {
        case .connection(let connection):
            return try await withConnection(connection, closure)
        case .client(let client):
            do {
                return try await client.withConnection { connection in
                    try await withConnection(
                        DatabaseConnectionMySQL(
                            connection: connection,
                            logger: logger
                        ),
                        closure
                    )
                }
            }
            catch let error as DatabaseError {
                throw error
            }
            catch {
                throw .connection(error)
            }
        }
    }

    /// Execute work inside a MySQL transaction.
    ///
    /// The closure runs between `START TRANSACTION` and `COMMIT` with rollback on failure.
    /// - Parameter closure: A closure that receives the MySQL connection.
    /// - Throws: A `DatabaseError` if transaction handling fails.
    /// - Returns: The query result produced by the closure.
    @discardableResult
    public func withTransaction<T>(
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {
        switch storage {
        case .connection(let connection):
            return try await withTransaction(connection, closure)
        case .client(let client):
            do {
                return try await client.withConnection { connection in
                    try await withTransaction(
                        DatabaseConnectionMySQL(
                            connection: connection,
                            logger: logger
                        ),
                        closure
                    )
                }
            }
            catch let error as DatabaseError {
                throw error
            }
            catch {
                throw .connection(error)
            }
        }
    }

    private func withConnection<T>(
        _ connection: DatabaseConnectionMySQL,
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {
        do {
            return try await closure(connection)
        }
        catch let error as DatabaseError {
            throw error
        }
        catch {
            throw .connection(error)
        }
    }

    private func withTransaction<T>(
        _ connection: DatabaseConnectionMySQL,
        _ closure: (Connection) async throws -> T
    ) async throws(DatabaseError) -> T {
        do {
            try await connection.run(query: "START TRANSACTION;") { _ in }
        }
        catch {
            throw DatabaseError.transaction(
                DatabaseTransactionErrorMySQL(
                    beginError: error
                )
            )
        }

        var closureHasFinished = false

        do {
            let result = try await closure(connection)
            closureHasFinished = true

            do {
                try await connection.run(query: "COMMIT;") { _ in }
            }
            catch {
                throw DatabaseError.transaction(
                    DatabaseTransactionErrorMySQL(commitError: error)
                )
            }

            return result
        }
        catch {
            var txError = DatabaseTransactionErrorMySQL()

            if !closureHasFinished {
                txError.closureError = error

                do {
                    try await connection.run(query: "ROLLBACK;") { _ in }
                }
                catch {
                    txError.rollbackError = error
                }
            }
            else {
                txError.commitError = error
            }

            throw DatabaseError.transaction(txError)
        }
    }
}
