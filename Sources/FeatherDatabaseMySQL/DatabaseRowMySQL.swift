//
//  DatabaseRowMySQL.swift
//  feather-database-mysql
//
//  Created by Tibor Bödecs on 2026. 01. 10.
//

public import FeatherDatabase
import MySQLNIO

public struct DatabaseRowMySQL: DatabaseRow {

    var row: MySQLNIO.MySQLRow

    public var columns: [String] {
        row.columnDefinitions.map(\.name)
    }

    public func contains(column: String) -> Bool {
        row.column(column) != nil
    }

    public func decodeNil(column: String) throws(DecodingError) -> Bool {
        guard let data = row.column(column) else {
            throw .keyNotFound(
                MySQLColumnKey(stringValue: column),
                .init(
                    codingPath: [],
                    debugDescription: "Missing data for column \(column)."
                )
            )
        }
        return data.type == .null || data.buffer == nil
    }

    struct SingleValueDecoder: Decoder, SingleValueDecodingContainer {

        var codingPath: [any CodingKey] { [] }
        var userInfo: [CodingUserInfoKey: Any] { [:] }

        let data: MySQLData

        func container<Key: CodingKey>(
            keyedBy: Key.Type
        ) throws(DecodingError) -> KeyedDecodingContainer<Key> {
            throw DecodingError.typeMismatch(
                KeyedDecodingContainer<Key>.self,
                .init(
                    codingPath: codingPath,
                    debugDescription: "Keyed decoding is not supported."
                )
            )
        }

        func unkeyedContainer() throws(DecodingError)
            -> any UnkeyedDecodingContainer
        {
            throw DecodingError.typeMismatch(
                (any UnkeyedDecodingContainer).self,
                .init(
                    codingPath: codingPath,
                    debugDescription: "Unkeyed decoding is not supported."
                )
            )
        }

        func singleValueContainer() throws(DecodingError)
            -> any SingleValueDecodingContainer
        {
            self
        }

        func decodeNil() -> Bool {
            data.type == .null || data.buffer == nil
        }

        func decode<T: Decodable>(
            _ type: T.Type
        ) throws(DecodingError) -> T {
            if let convertible = type as? any MySQLDataConvertible.Type {
                guard let value = convertible.init(mysqlData: data) else {
                    throw DecodingError.typeMismatch(
                        T.self,
                        .init(
                            codingPath: codingPath,
                            debugDescription:
                                "Could not convert data to \(T.self): \(data)."
                        )
                    )
                }
                return value as! T
            }

            throw DecodingError.typeMismatch(
                T.self,
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "Data is not convertible to \(T.self): \(data)."
                )
            )
        }
    }

    /// Decode a column value as the given type.
    ///
    /// This uses MySQL data conversion rules for `Decodable` types.
    /// - Parameters:
    ///   - column: The column name to decode.
    ///   - type: The expected type to decode as.
    /// - Throws: A `DecodingError` if the value cannot be decoded.
    /// - Returns: The decoded value.
    public func decode<T: Decodable>(
        column: String,
        as type: T.Type
    ) throws(DecodingError) -> T {
        guard let data = row.column(column) else {
            throw .dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Missing data for column \(column)."
                )
            )
        }
        do {
            return try T(from: SingleValueDecoder(data: data))
        }
        catch let error as DecodingError {
            throw error
        }
        catch {
            throw DecodingError.typeMismatch(
                T.self,
                .init(
                    codingPath: [],
                    debugDescription:
                        "Data is not convertible to \(T.self): \(data)."
                )
            )
        }
    }
}

private struct MySQLColumnKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
