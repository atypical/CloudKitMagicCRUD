//
//  Enums.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

import Foundation


public enum CRUDError: Error {
	// Legacy error cases
	case invalidRecord
	case invalidRecordID
	case cannotMapAllRecords
	case cannotDeleteRecord
	case cannotMapRecordToObject
	case noSurchRecord
	case needToSaveRefferencedRecord
	case invalidFieldType_Dictionary
	
	// New detailed error cases
	case invalidField(fieldName: String, typeName: String, message: String)
	case invalidReference(fieldName: String, typeName: String)
	case referenceSavingFailed(fieldName: String, typeName: String, underlyingError: Error)
	case fieldProcessingFailed(fieldName: String, typeName: String, underlyingError: Error)
	case recordExists(recordID: String, typeName: String)
	case recordNotFound(recordID: String, typeName: String)
	case circularReferenceDetected(fieldName: String, typeName: String)
	case operationFailed(operation: String, typeName: String, underlyingError: Error)
    
    // Additional error cases for async operations
    case recordAlreadyExists(recordName: String, typeName: String)
    case recordDoesNotExist(recordName: String, typeName: String)
}

extension CRUDError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .invalidRecord:
			return "The CloudKit record is invalid"
		case .invalidRecordID:
			return "The CloudKit record ID is invalid or missing"
		case .cannotMapAllRecords:
			return "Could not map all CloudKit records to objects"
		case .cannotDeleteRecord:
			return "Could not delete CloudKit record"
		case .cannotMapRecordToObject:
			return "Could not map CloudKit record to object"
		case .noSurchRecord:
			return "No such record found"
		case .needToSaveRefferencedRecord:
			return "Referenced record needs to be saved first"
		case .invalidFieldType_Dictionary:
			return "Invalid field type: Dictionary is not supported"
			
		// New detailed error cases
		case .invalidField(let fieldName, let typeName, let message):
			return "Invalid field '\(fieldName)' in type '\(typeName)': \(message)"
		case .invalidReference(let fieldName, let typeName):
			return "Invalid reference in field '\(fieldName)' of type '\(typeName)'"
		case .referenceSavingFailed(let fieldName, let typeName, let error):
			return "Failed to save reference for field '\(fieldName)' in type '\(typeName)': \(error.localizedDescription)"
		case .fieldProcessingFailed(let fieldName, let typeName, let error):
			return "Failed to process field '\(fieldName)' in type '\(typeName)': \(error.localizedDescription)"
		case .recordExists(let recordID, let typeName):
			return "Record already exists with ID '\(recordID)' for type '\(typeName)'"
		case .recordNotFound(let recordID, let typeName):
			return "Record not found with ID '\(recordID)' for type '\(typeName)'"
		case .circularReferenceDetected(let fieldName, let typeName):
			return "Circular reference detected in field '\(fieldName)' of type '\(typeName)'"
		case .operationFailed(let operation, let typeName, let error):
			return "Operation '\(operation)' failed for type '\(typeName)': \(error.localizedDescription)"
        case .recordAlreadyExists(let recordName, let typeName):
            return "Record already exists with name '\(recordName)' for type '\(typeName)'"
        case .recordDoesNotExist(let recordName, let typeName):
            return "Record does not exist with name '\(recordName)' for type '\(typeName)'"
		}
	}
	
	public var failureReason: String? {
		switch self {
		case .invalidField(_, _, let message):
			return message
		case .referenceSavingFailed(_, _, let error):
			return error.localizedDescription
		case .fieldProcessingFailed(_, _, let error):
			return error.localizedDescription
		case .operationFailed(_, _, let error):
			return error.localizedDescription
		default:
			return nil
		}
	}
}
