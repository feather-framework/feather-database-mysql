//
//  DatabaseTransactionErrorMySQL.swift
//  feather-database-mysql
//
//  Created by Tibor Bödecs on 2026. 01. 10.
//

public import FeatherDatabase

/// Transaction error details for MySQL operations.
///
/// Use this to capture errors from transaction phases.
public struct DatabaseTransactionErrorMySQL: DatabaseTransactionError {

    /// The source file where the error was created.
    ///
    /// This is captured with `#fileID` by default.
    public let file: String
    /// The source line where the error was created.
    ///
    /// This is captured with `#line` by default.
    public let line: Int

    /// The error thrown while beginning the transaction.
    ///
    /// Set when the `START TRANSACTION` step fails.
    public internal(set) var beginError: (any Error)?
    /// The error thrown inside the transaction closure.
    ///
    /// Set when the closure fails before commit.
    public internal(set) var closureError: (any Error)?
    /// The error thrown while committing the transaction.
    ///
    /// Set when the `COMMIT` step fails.
    public internal(set) var commitError: (any Error)?
    /// The error thrown while rolling back the transaction.
    ///
    /// Set when the `ROLLBACK` step fails.
    public internal(set) var rollbackError: (any Error)?

    /// Create a MySQL transaction error payload.
    ///
    /// Use this to record the errors that occurred during transaction handling.
    /// - Parameters:
    ///   - file: The source file identifier.
    ///   - line: The source line number.
    ///   - beginError: The error thrown while beginning the transaction.
    ///   - closureError: The error thrown inside the transaction closure.
    ///   - commitError: The error thrown while committing the transaction.
    ///   - rollbackError: The error thrown while rolling back the transaction.
    init(
        file: String = #fileID,
        line: Int = #line,
        beginError: (any Error)? = nil,
        closureError: (any Error)? = nil,
        commitError: (any Error)? = nil,
        rollbackError: (any Error)? = nil
    ) {
        self.file = file
        self.line = line
        self.beginError = beginError
        self.closureError = closureError
        self.commitError = commitError
        self.rollbackError = rollbackError
    }
}
