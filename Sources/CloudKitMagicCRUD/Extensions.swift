//
//  Extensions.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

import CloudKit
import Foundation

// Add URL extension for contentAsData
public extension URL {
    var contentAsData: Data? {
        try? Data(contentsOf: self)
    }
}

public typealias CKMCursor = CKQueryOperation.Cursor
public typealias CKMRecordName = String
public typealias CKRecordAsyncResult = (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                                        queryCursor: CKQueryOperation.Cursor?)
public typealias CKMRecordAsyncResult = (Result<(records: [Any],
                                                 queryCursor: CKMCursor?,
                                                 partialErrors: [CKMRecordName:Error]), Error>)

extension CKRecord {
    /// Converts the record to a dictionary.
    public var asDictionary: [String: Any] {
        var result: [String: Any] = [:]
        result["recordName"] = self.recordID.recordName
        result["createdBy"] = self.creatorUserRecordID?.recordName
        result["createdAt"] = self.creationDate
        result["modifiedBy"] = self.lastModifiedUserRecordID?.recordName
        result["modifiedAt"] = self.modificationDate
        result["changeTag"] = self.recordChangeTag

        // Iterate over all keys in the record
        for key in self.allKeys() {
            // If value is Date
            if let value = self.value(forKey: key) as? Date {
                result[key] = value.timeIntervalSinceReferenceDate
            }
            // If value is an array of Dates
            else if let value = self.value(forKey: key) as? [Date] {
                result[key] = value.map { $0.timeIntervalSinceReferenceDate }
            }

            // If value is a reference to another object, get the other object and transform to dictionary
            else if let value = self.value(forKey: key) as? CKRecord.Reference {
                result[key] = value.syncLoad()
            }
            // If value is an array of references
            else if let value = self.value(forKey: key) as? [CKRecord.Reference] {
                if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
                    result[key] = value.syncLoadAll()
                } else {
                    // Fallback for older watchOS versions
                    result[key] = value.map { $0.syncLoad() }
                }
            }

            // If value is an Asset, convert to Data
            else if let value = self.value(forKey: key) as? CKAsset {
                result[key] = value.fileURL?.contentAsData
            }
            // If value is an array of Assets
            else if let value = self.value(forKey: key) as? [CKAsset] {
                result[key] = value.map { $0.fileURL?.contentAsData }
            } else {
                result[key] = self.value(forKey: key)
            }
        }
        return result
    }
    
    /// Converts the record to a dictionary asynchronously.
    /// This method properly handles reference cycles by using a tracking set.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public func asDictionaryAsync(loadedRecords: Set<String> = []) async throws -> [String: Any] {
        var result: [String: Any] = [:]
        result["recordName"] = self.recordID.recordName
        result["createdBy"] = self.creatorUserRecordID?.recordName
        result["createdAt"] = self.creationDate
        result["modifiedBy"] = self.lastModifiedUserRecordID?.recordName
        result["modifiedAt"] = self.modificationDate
        result["changeTag"] = self.recordChangeTag
        
        // Track records being loaded to prevent cycles
        var loadedRecords = loadedRecords
        loadedRecords.insert(self.recordID.recordName)
        
        // Iterate over all keys in the record
        for key in self.allKeys() {
            // If value is Date
            if let value = self.value(forKey: key) as? Date {
                result[key] = value.timeIntervalSinceReferenceDate
            }
            // If value is an array of Dates
            else if let value = self.value(forKey: key) as? [Date] {
                result[key] = value.map { $0.timeIntervalSinceReferenceDate }
            }
            
            // If value is a reference to another object, get the other object and transform to dictionary
            else if let value = self.value(forKey: key) as? CKRecord.Reference {
                // Check for cycles
                if loadedRecords.contains(value.recordID.recordName) {
                    // Handle cycle by including just the reference information
                    result[key] = ["recordName": value.recordID.recordName, "__isCycleReference": true]
                } else {
                    result[key] = try await value.asyncLoad(loadedRecords: loadedRecords)
                }
            }
            // If value is an array of references
            else if let value = self.value(forKey: key) as? [CKRecord.Reference] {
                result[key] = try await value.asyncLoadAll(loadedRecords: loadedRecords)
            }
            
            // If value is an Asset, convert to Data
            else if let value = self.value(forKey: key) as? CKAsset {
                result[key] = value.fileURL?.contentAsData
            }
            // If value is an array of Assets
            else if let value = self.value(forKey: key) as? [CKAsset] {
                result[key] = value.map { $0.fileURL?.contentAsData }
            } else {
                result[key] = self.value(forKey: key)
            }
        }
        return result
    }

    /// Converts the record to a reference.
    var asReference: CKRecord.Reference {
        return CKRecord.Reference(recordID: self.recordID, action: .none)
    }

    /// Checks if the record has a cycle.
    func haveCycle(references: Set<String> = []) -> Bool {
        var references = references
        references.insert(self.recordID.recordName)
        let childReferences = Set(self.allKeys().compactMap { (value(forKey: $0) as? CKRecord.Reference)?.recordID.recordName })

        // If there's an intersection, there's a cycle
        guard childReferences.intersection(references).count == 0 else { return true }

        let childRecords = childReferences.compactMap { CKMDefault.getFromCache($0) }
        let referencesUnion = childReferences.union(references)

        for item in childRecords {
            if item.haveCycle(references: referencesUnion) {
                return true
            }
        }
        return false
    }
}

extension CKRecord.Reference {
    /// Loads the referenced record.
    /// This method is synchronous and will block the current thread.
    /// It's recommended to use asyncLoad() on iOS 15+ for better performance.
    @available(iOS, deprecated: 15.0, message: "Use asyncLoad() instead")
    @available(macOS, deprecated: 12.0, message: "Use asyncLoad() instead")
    @available(tvOS, deprecated: 15.0, message: "Use asyncLoad() instead")
    @available(watchOS, deprecated: 8.0, message: "Use asyncLoad() instead")
    func syncLoad() -> [String: Any]? {
        // On iOS 15+, use the async method wrapped in a Task
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            var result: [String: Any]?
            let semaphore = DispatchSemaphore(value: 0)
            
            Task {
                do {
                    result = try await self.asyncLoad()
                } catch {
                    debugPrint("Error loading reference: \(error)")
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            return result
        }
        
        // Legacy implementation for older iOS versions
        let recordName: String = self.recordID.recordName
        
        // If the record is cached, return it
        if let cachedRecord = CKMDefault.getFromCache(recordName) {
            return cachedRecord.asDictionary
        }
        
        // Otherwise fetch it from CloudKit
        var result: [String: Any]?
        CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in

            // Got error
            if let error = error {
                debugPrint("Cannot read associated record \(recordName), \(error)")

            } // Got Record
            else if let record = record {
                CKMDefault.addToCache(record)
                result = record.asDictionary
            }
            CKMDefault.semaphore.signal()
        })
        CKMDefault.semaphore.wait()
        return result
    }
    
    /// Loads the referenced record asynchronously.
    /// This method properly handles reference cycles by using a tracking set.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func asyncLoad(loadedRecords: Set<String> = []) async throws -> [String: Any]? {
        let recordName: String = self.recordID.recordName
        
        // Check if this record would create a cycle
        if loadedRecords.contains(recordName) {
            // Return a simplified reference instead of throwing an error
            return ["recordName": recordName, "__isCycleReference": true]
        }
        
        // If the record is cached, return it
        if let record = CKMDefault.getFromCache(recordName) {
            return try await record.asDictionaryAsync(loadedRecords: loadedRecords)
        }
        
        // Fetch the record from CloudKit
        do {
            let record = try await CKMDefault.database.record(for: self.recordID)
            CKMDefault.addToCache(record)
            return try await record.asDictionaryAsync(loadedRecords: loadedRecords)
        } catch {
            CKMDefault.logError(error)
            return nil
        }
    }
}

/// Extension to handle arrays of references
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Array where Element == CKRecord.Reference {
    /// Loads all referenced records synchronously.
    /// This method is synchronous and will block the current thread.
    /// It's recommended to use asyncLoadAll() on iOS 15+ for better performance.
    func syncLoadAll() -> [[String: Any]?] {
        // On iOS 15+, use the async method wrapped in a Task
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            var result: [[String: Any]?] = []
            let semaphore = DispatchSemaphore(value: 0)
            
            Task {
                do {
                    result = try await self.asyncLoadAll()
                } catch {
                    debugPrint("Error loading references: \(error)")
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            return result
        }
        
        // Legacy implementation for older iOS versions
        return self.map { $0.syncLoad() }
    }
    
    /// Loads all referenced records asynchronously.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func asyncLoadAll(loadedRecords: Set<String> = []) async throws -> [[String: Any]?] {
        var results: [[String: Any]?] = []
        var updatedLoadedRecords = loadedRecords
        
        for reference in self {
            let result = try await reference.asyncLoad(loadedRecords: updatedLoadedRecords)
            results.append(result)
            
            // Add this record to the loaded records set to track cycles
            if let result = result, let recordName = result["recordName"] as? String {
                updatedLoadedRecords.insert(recordName)
            }
        }
        
        return results
    }
}

public extension CKAsset {
    /// Initializes an asset with data.
    convenience init(data: Data) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString + ".data"))
        do {
            try data.write(to: url)
        } catch let e as NSError {
            debugPrint("Error! \(e)")
        }
        self.init(fileURL: url)
    }

    /// Returns the asset data.
    var data: Data? {
        return self.fileURL?.contentAsData
    }
}

public extension Optional where Wrapped == String {
    /// Checks if the string is empty.
    var isEmpty: Bool {
        return self?.isEmpty ?? true
    }
}

public extension String {
    /// Deletes the suffix from the string.
    func deleting(suffix: String) -> String {
        guard self.hasSuffix(suffix) else { return self }
        return String(self.dropLast(suffix.count))
    }
}

/**
 - Description:
 A String that has "⇩" as last character if its SortDescriptor is descending.
 Set the descriptor as descending using (ckSort.descending).
 */
public typealias CKSortDescriptor = NSString
extension NSString {
    /// For use with SortDescriptor
    class CK {
        private var text: String
        var isAscending: Bool { text.last != "⇩" }
        var isDescending: Bool { text.last == "⇩" }
        var ascending: String { return isAscending ? text : String(text.dropLast()) }
        var v: String { return isDescending ? text : text + "⇩" }
        var descriptor: NSSortDescriptor { NSSortDescriptor(key: ascending, ascending: isAscending) }
        init(_ text: NSString) { self.text = String(text) }
    }

    /**
     - Description:
     Elements for use with SortDescriptors
     */
    var ckSort: CK { CK(self) }
}

public extension Array where Element == CKSortDescriptor {
    /// Returns an array of sort descriptors.
    var ckSortDescriptors: [NSSortDescriptor] { self.map { $0.ckSort.descriptor } }
}

public extension Date {
    /// Initializes a date with a string and format.
    init(date: String, format: String? = nil) {
        self.init()
        self.set(date: date, format: format)
    }

    /// Sets the date with a string and format.
    mutating func set(date: String, format: String? = nil) {

        let format = format ?? (date.count == 16 ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd")
        let formatter = DateFormatter()
        formatter.dateFormat = format
        guard let newDate = formatter.date(from: date) else {
            debugPrint("date \(date) in format \(format) does not result in a valid date")
            return
        }
        self = newDate
    }
}

// Global Functions

/// Checks if the object type is a basic type (Number, String, Date).
func isBasicType(_ value: Any) -> Bool {
    let typeDescription = String(reflecting: type(of: value))
    guard typeDescription.contains("Swift") || typeDescription.contains("Foundation") else { return false }
    return typeDescription.contains("Int") || typeDescription.contains("Float") || typeDescription.contains("Double") || typeDescription.contains("String") || typeDescription.contains("Date") || typeDescription.contains("Bool")
}

public extension NSPointerArray {
    /// Adds an object to the array.
    func addObject(_ object: AnyObject?) {
        guard let strongObject = object else { return }

        let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
        addPointer(pointer)
    }

    /// Inserts an object at a specific index.
    func insertObject(_ object: AnyObject?, at index: Int) {
        guard index < count, let strongObject = object else { return }

        let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
        insertPointer(pointer, at: index)
    }

    /// Replaces an object at a specific index.
    func replaceObject(at index: Int, withObject object: AnyObject?) {
        guard index < count, let strongObject = object else { return }

        let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
        replacePointer(at: index, withPointer: pointer)
    }

    /// Returns the object at a specific index.
    func object(at index: Int) -> AnyObject? {
        guard index < count, let pointer = self.pointer(at: index) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Removes the object at a specific index.
    func removeObject(at index: Int) {
        guard index < count else { return }

        removePointer(at: index)
    }
}

public extension Optional {
    /// Returns the wrapped type.
    func wrappedType() -> Any.Type {
        return Wrapped.self
    }
}

@available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
extension CKMPreparedRecord {
    /// Saves all pending references in the record and returns the updated CKRecord.
    ///
    /// - Parameter savedRecord: The CKRecord that was saved.
    /// - Returns: The updated CKRecord with all pending references saved.
    /// - Throws: PrepareRecordError if there is an error saving a pending reference.
    public func dispatchPending(for savedRecord: CKRecord) async throws -> CKRecord {
        self.record = savedRecord
        self.objectSaving.recordName = record.recordID.recordName
        CKMDefault.addToCache(record)

        guard let _ = objectSaving.recordName else {
            throw PrepareRecordError.CannotDispatchPendingWithoutSavedRecord("Object \(objectSaving) must have a recordName")
        }

        guard !pending.isEmpty else { return record }

        for item in pending {
            let savedBranchRecord = try await item.cyclicReferenceBranch.ckSaveAsync()

            guard let referenceID = savedBranchRecord.recordName else {
                throw PrepareRecordError.ErrorSavingReferenceObject("\(item.pendingCyclicReferenceName) in \(self.record.recordType) - Record saved without reference")
            }

            if let ckRecord = try await self.updateRecord(with: referenceID, in: item) {
                return ckRecord
            }
        }
        return self.record
    }

    /// Updates the record with a reference and returns the updated CKRecord.
    public func updateRecord(with reference: String, in item: CKMPreparedRecord.Reference) async throws -> CKRecord? {
        let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: reference), action: .none)
        let referenceField = item.pendingCyclicReferenceName
        // If item is an array of references
        if var referenceArray = self.record.value(forKey: referenceField) as? [CKRecord.Reference] {
            referenceArray.append(reference)
            self.record.setValue(referenceArray, forKey: referenceField)
        } else {
            // If item is a single reference
            self.record.setValue(reference, forKey: referenceField)
        }

        if self.allPendingValuesFilled {
            let record = try await CKMDefault.database.save(self.record)
            CKMDefault.addToCache(record)
            return record
        }
        return nil
    }

    enum PrepareRecordError: Swift.Error {
        case CannotDispatchPendingWithoutSavedRecord(String)
        case ErrorSavingReferenceObject(String)
    }
}
