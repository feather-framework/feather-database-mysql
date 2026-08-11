//
//  DatabaseConnectionMySQL.swift
//  feather-database-mysql
//
//  Created by Tibor Bödecs on 2026. 01. 10.
//

import FeatherDatabase
import MySQLNIO
import NIOCore

extension DatabaseQuery {

    fileprivate struct MySQLQuery {
        var sql: String
        var bindings: [MySQLData]
    }

    fileprivate func toMySQLQuery() -> MySQLQuery {
        var mysqlSQL = sql
        var mysqlBindings: [MySQLData] = []

        for binding in bindings {
            let idx = binding.index + 1
            mysqlSQL =
                mysqlSQL
                .replacing("{{\(idx)}}", with: "?")

            switch binding.binding {
            case .bool(let value):
                mysqlBindings.append(.init(bool: value))
            case .int(let value):
                mysqlBindings.append(.init(int: value))
            case .double(let value):
                mysqlBindings.append(.init(double: value))
            case .string(let value):
                mysqlBindings.append(.init(string: value))
            }
        }

        return .init(
            sql: mysqlSQL,
            bindings: mysqlBindings
        )
    }
}

public struct DatabaseConnectionMySQL: DatabaseConnection {

    public typealias RowSequence = DatabaseRowSequenceMySQL

    let connection: MySQLNIO.MySQLConnection

    /// Execute a MySQL query on this connection.
    ///
    /// This wraps `MySQLNIO` query execution and maps errors.
    /// - Parameters:
    ///  - query: The MySQL query to execute.
    ///  - handler: A closure that transforms the result into a generic value.
    /// - Throws: A `DatabaseError` if the query fails.
    /// - Returns: A query result containing the returned rows.
    @discardableResult
    public func run<T: Sendable>(
        query: DatabaseQuery,
        _ handler: (RowSequence) async throws -> T = { $0 }
    ) async throws(DatabaseError) -> T {
        do {
            let mysqlQuery = query.toMySQLQuery()
            let rows =
                try await connection.query(
                    mysqlQuery.sql,
                    mysqlQuery.bindings
                )
                .get()

            return try await handler(
                DatabaseRowSequenceMySQL(
                    elements: rows.map {
                        .init(
                            row: $0
                        )
                    }
                )
            )
        }
        catch {
            throw .query(error)
        }
    }
}
