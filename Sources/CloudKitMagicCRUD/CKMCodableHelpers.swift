//
//  CKMCodableHelpers.swift
//  CloudKitMagicCRUD
//
//  Created on 04/2025
//

import CloudKit
import Foundation

/// Helper methods for Codable implementation with CloudKit
public enum CKMCodableHelpers {
    
    /// Decodes a CloudKit record dictionary into a Codable object
    /// - Parameter dictionary: Dictionary representation of a CloudKit record
    /// - Returns: Decoded object of type T
    /// - Throws: Error if decoding fails
    public static func decode<T: Decodable>(_ dictionary: [String: Any]) throws -> T {
        // Create a sanitized copy of the dictionary that's safe for JSON serialization
        let sanitizedDictionary = sanitizeForJSON(dictionary)
        
        let data = try JSONSerialization.data(withJSONObject: sanitizedDictionary, options: [])
        let decoder = JSONDecoder()
        
        // Configure decoder to handle special types
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timeInterval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected date value")
        }
        
        // Configure data decoding strategy
        decoder.dataDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let base64String = try? container.decode(String.self) {
                if let data = Data(base64Encoded: base64String) {
                    return data
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected base64 data")
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    /// Encodes a Codable object into a dictionary suitable for CloudKit
    /// - Parameter object: The object to encode
    /// - Returns: Dictionary representation of the object
    /// - Throws: Error if encoding fails
    public static func encode<T: Encodable>(_ object: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        
        // Configure encoder to handle special types
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        
        // Configure data encoding strategy
        encoder.dataEncodingStrategy = .custom { data, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(data.base64EncodedString())
        }
        
        let data = try encoder.encode(object)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw EncodingError.invalidValue(object, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert encoded data to dictionary"
            ))
        }
        
        return dictionary
    }
    
    /// Sanitizes a dictionary for JSON serialization
    /// - Parameter dictionary: Dictionary to sanitize
    /// - Returns: Sanitized dictionary
    public static func sanitizeForJSON(_ dictionary: [String: Any]) -> [String: Any] {
        var sanitized = [String: Any]()
        for (key, value) in dictionary {
            if let date = value as? Date {
                // Convert Date objects to timeIntervalSinceReferenceDate (Double)
                sanitized[key] = date.timeIntervalSinceReferenceDate
            } else if let dateArray = value as? [Date] {
                // Handle arrays of Date objects
                sanitized[key] = dateArray.map { $0.timeIntervalSinceReferenceDate }
            } else if let data = value as? Data {
                // Convert Data objects to base64 strings
                sanitized[key] = data.base64EncodedString()
            } else if let dataArray = value as? [Data] {
                // Handle arrays of Data objects
                sanitized[key] = dataArray.map { $0.base64EncodedString() }
            } else if value is NSNull {
                // Skip null values
                continue
            } else if let nestedDict = value as? [String: Any] {
                // Handle nested dictionaries recursively
                sanitized[key] = sanitizeForJSON(nestedDict)
            } else if let nestedArray = value as? [Any] {
                // Handle nested arrays recursively
                sanitized[key] = sanitizeArray(nestedArray)
            } else if let swiftData = value as? NSData {
                // Handle NSData/NSSwiftData objects
                let data = Data(referencing: swiftData)
                sanitized[key] = data.base64EncodedString()
            } else {
                // Pass other values through
                sanitized[key] = value
            }
        }
        return sanitized
    }
    
    /// Sanitizes an array for JSON serialization
    /// - Parameter array: Array to sanitize
    /// - Returns: Sanitized array
    public static func sanitizeArray(_ array: [Any]) -> [Any] {
        return array.map { value in
            if let date = value as? Date {
                return date.timeIntervalSinceReferenceDate
            } else if let data = value as? Data {
                return data.base64EncodedString()
            } else if let nestedDict = value as? [String: Any] {
                return sanitizeForJSON(nestedDict)
            } else if let nestedArray = value as? [Any] {
                return sanitizeArray(nestedArray)
            } else if let swiftData = value as? NSData {
                let data = Data(referencing: swiftData)
                return data.base64EncodedString()
            } else {
                return value
            }
        }
    }
    
    /// Resolves references in a dictionary
    /// - Parameter dictionary: Dictionary containing references
    /// - Returns: Dictionary with resolved references
    /// - Throws: Error if reference resolution fails
    public static func resolveReferences(_ dictionary: [String: Any]) throws -> [String: Any] {
        var result = dictionary
        
        for (key, value) in dictionary {
            if let referenceDict = value as? [String: Any],
               let recordName = referenceDict["recordName"] as? String {
                // This looks like a reference
                if let record = CKMDefault.getFromCache(recordName) {
                    result[key] = try resolveReferences(record.asDictionary)
                }
            } else if let referenceArray = value as? [[String: Any]] {
                // This might be an array of references
                var resolvedArray: [[String: Any]] = []
                for item in referenceArray {
                    if let recordName = item["recordName"] as? String,
                       let record = CKMDefault.getFromCache(recordName) {
                        resolvedArray.append(try resolveReferences(record.asDictionary))
                    } else {
                        resolvedArray.append(item)
                    }
                }
                result[key] = resolvedArray
            }
        }
        
        return result
    }
}

/// Protocol for objects that can customize their Codable implementation with CloudKit
public protocol CKMCustomCodable: CKMCloudable {
    /// Custom encode implementation for CloudKit
    /// - Returns: Dictionary representation of the object
    /// - Throws: Error if encoding fails
    func ckCustomEncode() throws -> [String: Any]
    
    /// Custom decode implementation for CloudKit
    /// - Parameter dictionary: Dictionary representation of a CloudKit record
    /// - Throws: Error if decoding fails
    static func ckCustomDecode(from dictionary: [String: Any]) throws -> Self
}

/// Default implementation for CKMCustomCodable
extension CKMCustomCodable {
    public func ckCustomEncode() throws -> [String: Any] {
        return try CKMCodableHelpers.encode(self)
    }
    
    public static func ckCustomDecode(from dictionary: [String: Any]) throws -> Self {
        return try CKMCodableHelpers.decode(dictionary)
    }
}

/// Extension to CKMCloudable to use the Codable helpers
extension CKMCloudable {
    /// Load from a dictionary with improved error handling
    public static func loadWithReferences(from dictionary: [String: Any]) throws -> Self {
        do {
            let resolvedDictionary = try CKMCodableHelpers.resolveReferences(dictionary)
            
            if let customCodable = Self.self as? CKMCustomCodable.Type {
                return try customCodable.ckCustomDecode(from: resolvedDictionary) as! Self
            } else {
                return try CKMCodableHelpers.decode(resolvedDictionary)
            }
        } catch {
            CKMDefault.logError(error)
            throw CRUDError.cannotMapRecordToObject
        }
    }
}
