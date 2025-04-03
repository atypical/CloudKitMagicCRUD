//
//  CKCloudable.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 22/08/20.
//  Copyright 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

import CloudKit

public protocol CKMCloudable:Codable {
	var recordName:String? { get set }
    
    /// Optional system fields that can be populated from CloudKit
    var createdBy: String? { get }
    var createdAt: Date? { get }
    var modifiedBy: String? { get }
    var modifiedAt: Date? { get }
    var changeTag: String? { get }
}

/// Basic Record Management
extension CKMCloudable {
	
	public static var isClassType:Bool {return (Self.self is AnyClass)}
	public var isClassType:Bool {return Self.isClassType}
	
	/**
	Get or set the recordType name
	The default value is the type (class or struct) name
	*/
	public static var ckRecordType: String {
		get { CKMDefault.getRecordTypeFor(type: Self.self) }
		set { CKMDefault.setRecordTypeFor(type: Self.self, recordName: newValue) }
	}
	
	public static var ckIsCachable:Bool {
		get { CKMDefault.get(isCacheable: Self.self) }
		set { CKMDefault.set(type: Self.self, isCacheable: newValue) }
	}
	
	public var reference:CKRecord.Reference? {
		guard let recordName = self.recordName else {return nil}
		return CKRecord.Reference(recordID: CKRecord.ID(recordName: recordName), action: .none)
		
	}
	
	public var referenceInCacheOrNull:CKRecord.Reference? {
		if let reference = self.reference {
			if let _ = CKMDefault.getFromCache(reference.recordID.recordName) {
				return reference
			}
		} // else
		return nil
	}
    
    /// Creates a new CKRecord based on the current configuration
    @available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
    public func createCKRecord() -> CKRecord {
        if let recordName = self.recordName {
            return CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: recordName))
        } else if CKMDefault.configuration.useCloudKitRecordIDAsIdentifier {
            let recordID = CKMDefault.generateRecordID(for: self)
            return CKRecord(recordType: Self.ckRecordType, recordID: recordID)
        } else {
            return CKRecord(recordType: Self.ckRecordType)
        }
    }
	
	/// Return true if this type has a cyclic reference
	public func haveCycle(with object:CKMCloudable? = nil, previousPath:[AnyObject] = [])->Bool {
		let object = object ?? self
		// If not a class type, don't waste time
		if !self.isClassType {return false}
		
		let mirror = Mirror(reflecting: self)
		for field in mirror.children{
			let value_object = field.value as AnyObject
			if let cloudRecord = value_object as? CKMCloudable {
				let value = cloudRecord as AnyObject
				if value === (object as AnyObject) { return true }
				if (previousPath.contains{value === $0}) { return false }
				var previousPath = previousPath
				previousPath.append(value)
				return cloudRecord.haveCycle(with: object, previousPath: previousPath)
			}
		}
		return false
	}
	
	// MARK: - Deprecated Synchronous Methods
	
	@available(*, deprecated, message: "Use async version instead: referenceSavingRecordIfNullAsync()")
	public var referenceSavingRecordIfNull:CKRecord.Reference? {
		if let reference = self.referenceInCacheOrNull {
			return reference
		}
		// else
		var savedReference:CKRecord.Reference? = nil
		
		// Start asynchronous operation
        
        if #available(watchOS 8.0, *) {
            self.ckSave(then: { result in
                switch result {
                case .success(let savedRecord):
                    savedReference = (savedRecord as? CKMCloudable)?.reference
                case .failure(let error):
                    debugPrint("error saving record \(self.recordName ?? "without recordName") \n\(error)")
                }
                CKMDefault.semaphore.signal()
            })
        } else {
            // Fallback on earlier versions
        }
		// End asynchronous operation
		CKMDefault.semaphore.wait()
		
		return savedReference
	}
	
	// MARK: - Modern Async Methods
	
	@available(iOS 13.0, watchOS 8.0, macOS 10.15, tvOS 13.0, *)
	public func referenceSavingRecordIfNullAsync() async throws -> CKRecord.Reference? {
		if let reference = self.referenceInCacheOrNull {
			return reference
		}
		
		do {
			let savedRecord = try await self.ckSave()
			return savedRecord.reference
		} catch {
			debugPrint("Error saving record \(self.recordName ?? "without recordName"): \(error.localizedDescription)")
			throw error
		}
	}
	
	@available(*, deprecated, message: "Use async version instead: prepareCKRecordAsync()")
	@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
	public func prepareCKRecord()throws ->CKMPreparedRecord {
		let ckRecord:CKRecord = {
			var ckRecord:CKRecord?
			if let recordName = self.recordName {
				CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
					
					ckRecord = record
					CKMDefault.semaphore.signal()
				})
				
				CKMDefault.semaphore.wait()
				if let record = ckRecord {return record}
				// else
				return CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: recordName))
			} // else
			return CKRecord(recordType: Self.ckRecordType)
		}()
		let preparedRecord = CKMPreparedRecord(for: self, in:ckRecord)
		let mirror = Mirror(reflecting: self)
		
		for field in mirror.children{
			// Process values from a mirror
			
			var value = field.value
			guard !"\(value)".elementsEqual("nil") else {continue} // Skip nil values
			guard let key = field.label else { fatalError("Type \(mirror) have field without label.") }
			
			//MARK: Treatment of all possible types
			
			if field.label?.elementsEqual("recordName") ?? false
				|| field.label?.elementsEqual("createdBy") ?? false
				|| field.label?.elementsEqual("createdAt") ?? false
				|| field.label?.elementsEqual("modifiedBy") ?? false
				|| field.label?.elementsEqual("modifiedAt") ?? false
				|| field.label?.elementsEqual("changeTag") ?? false {
				// do nothing
			}
			
			// If field is a basic type (Number, String, Date or array of these elements)
			else if  isBasicType(field.value) {
				ckRecord.setValue(value, forKey: key)
			}
			
			// If field is Data or [Data], convert to Asset or [Asset]
			else if let data = value as? Data {
				value = CKAsset(data: data)
				ckRecord.setValue(value, forKey: key)
			}
			
			else if let datas = value as? [Data] {
				value = datas.map {CKAsset(data: $0)}
				ckRecord.setValue(value, forKey: key)
			}
			
			// If field is CKCloudable, get the reference
			else if let value = (field.value as AnyObject) as? CKMCloudable {
				// If reference doesn't have null recordName, all is well
				if let reference = value.referenceInCacheOrNull {
					ckRecord.setValue(reference, forKey: key)
				}
				// If not, and my recordName is filled, save the dependency and continue
				else if let _ = self.recordName {
					if let reference = value.referenceSavingRecordIfNull {
						ckRecord.setValue(reference, forKey: key)
					} else {
						debugPrint("----------------------------------")
						debugPrint("Cannot save record for \(key) in \(Self.ckRecordType)")
						dump(value)
						debugPrint("----------------------------------")
					}
				}
				/// If my recordName is not filled and has cyclic reference, store object for later
				else if value.haveCycle(with: self) {
					preparedRecord.add(value: value, forKey: key)
				}
			}
			
			// If field is [CKCloudable] Pega a referência
			else if let value = field.value as? [CKMCloudable] {
				var references:[CKRecord.Reference] = []
				for item in value {
					if let reference = item.referenceSavingRecordIfNull {
						references.append(reference)
					} else {
						debugPrint("Invalid Field in \(mirror).\(key) \n Data:")
						dump(item)
						throw CRUDError.invalidRecordID
					}
				}
				ckRecord.setValue(references, forKey: key)
				
			}
			
			else {
				debugPrint("WARNING: Untratable type\n    \(key): \(type(of: field.value)) = \(field.value)")
				continue
			}
		}
		
		return preparedRecord
	}
	
	@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
	public func prepareCKRecordAsync() async throws -> CKMPreparedRecord {
		let ckRecord = self.createCKRecord()
		
		let preparedRecord = CKMPreparedRecord(for: self, in: ckRecord)
		let mirror = Mirror(reflecting: self)
		
		for field in mirror.children {
			var value = field.value
			guard !"\(value)".elementsEqual("nil") else { continue } // Skip nil values
			
			guard let key = field.label else {
				throw CRUDError.invalidField(fieldName: "unknown", typeName: "\(mirror)", message: "Field without label")
			}
			
			// Skip system fields
			if field.label?.elementsEqual("recordName") ?? false
				|| field.label?.elementsEqual("createdBy") ?? false
				|| field.label?.elementsEqual("createdAt") ?? false
				|| field.label?.elementsEqual("modifiedBy") ?? false
				|| field.label?.elementsEqual("modifiedAt") ?? false
				|| field.label?.elementsEqual("changeTag") ?? false {
				continue
			}
			
			do {
				// Handle basic types (Number, String, Date, or arrays of these elements)
				if isBasicType(field.value) {
					ckRecord.setValue(value, forKey: key)
				}
				// Handle Data or [Data], convert to Asset or [Asset]
				else if let data = value as? Data {
					value = CKAsset(data: data)
					ckRecord.setValue(value, forKey: key)
				}
				else if let datas = value as? [Data] {
					value = datas.map { CKAsset(data: $0) }
					ckRecord.setValue(value, forKey: key)
				}
				// Handle CKCloudable references
				else if let value = (field.value as AnyObject) as? CKMCloudable {
					// If reference has recordName, use it
					if let reference = value.referenceInCacheOrNull {
						ckRecord.setValue(reference, forKey: key)
					}
					// If this record has a recordName, save the dependency
					else if self.recordName != nil {
						do {
                            if #available(watchOS 8.0, *) {
                                if let reference = try await value.referenceSavingRecordIfNullAsync() {
                                    ckRecord.setValue(reference, forKey: key)
                                } else {
                                    throw CRUDError.invalidReference(fieldName: key, typeName: Self.ckRecordType)
                                }
                            } else {
                                // Fallback on earlier versions
                            }
						} catch let error {
							throw CRUDError.referenceSavingFailed(fieldName: key, typeName: Self.ckRecordType, underlyingError: error)
						}
					}
					// If this record doesn't have a recordName and has a cyclic reference, store for later
					else if value.haveCycle(with: self) {
						preparedRecord.add(value: value, forKey: key)
					}
				}
				// Handle arrays of CKCloudable
				else if let value = field.value as? [CKMCloudable] {
					var references: [CKRecord.Reference] = []
					for (index, item) in value.enumerated() {
						do {
                            if #available(watchOS 8.0, *) {
                                if let reference = try await item.referenceSavingRecordIfNullAsync() {
                                    references.append(reference)
                                } else {
                                    throw CRUDError.invalidReference(fieldName: "\(key)[\(index)]", typeName: Self.ckRecordType)
                                }
                            } else {
                                // Fallback on earlier versions
                            }
						} catch let error {
							throw CRUDError.referenceSavingFailed(fieldName: "\(key)[\(index)]", typeName: Self.ckRecordType, underlyingError: error)
						}
					}
					ckRecord.setValue(references, forKey: key)
				}
				// Handle unsupported types
				else {
					debugPrint("WARNING: Unsupported type\n    \(key): \(type(of: field.value)) = \(field.value)")
					continue
				}
			} catch let error {
				CKMDefault.logError(error)
				throw CRUDError.fieldProcessingFailed(fieldName: key, typeName: Self.ckRecordType, underlyingError: error)
			}
		}
		
		return preparedRecord
	}
	
	/**
	Saves the object in iCloud, returning in a completion a Result Type
		Cases:
			.success(let record:CKMRecord) -> The saved record, with correct Object Type, in a Any shell.  Just cast this to it's original type.
			.failure(let error) an error
	*/
	@available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
	public func ckSave(then completion:@escaping (Result<Any, Error>)->Void) {
		Task {
			do {
				let ckPreparedRecord = try await self.prepareCKRecordAsync()
				let record = try await CKMDefault.database.save(ckPreparedRecord.record)
				
				ckPreparedRecord.dispatchPending(for: record) { result in
					switch result {
					case .success(let savedRecord):
						do {
							let object = try Self.load(from: savedRecord.asDictionary)
							completion(.success(object))
						} catch {
							completion(.failure(CRUDError.cannotMapRecordToObject))
						}
					case .failure(let error):
						completion(.failure(error))
					}
				}
			} catch {
				completion(.failure(error))
			}
		}
	}
	
	@available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
	public func ckSaveAsync() async throws -> Self {
		let ckPreparedRecord = try await self.prepareCKRecordAsync()
		let record = try await CKMDefault.database.save(ckPreparedRecord.record)
		let finalRecord = try await ckPreparedRecord.dispatchPendingAsync(for: record)
		let object = try Self.load(from: finalRecord.asDictionary)
		return object
	}
	
	public func ckDelete(then completion:@escaping (Result<String, Error>)->Void) {
		guard let recordName = self.recordName else { return }
        
            CKMDefault.database.delete(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (_, error) -> Void in
                
                    // Got error
                if let error = error {
                    completion(.failure(error))
                    return
                }
                    // else
                completion(.success(recordName))
                CKMDefault.removeFromCache(recordName)
            })
        
	}
	
	@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
	public func ckDeleteAsync() async throws -> CKRecord.ID {
		guard let recordName = self.recordName else { throw CRUDError.invalidRecordID }
		let recordID = try await CKMDefault.database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
		CKMDefault.removeFromCache(recordName)
		return recordID
	}
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func ckDeleteCascadeAsync() async throws -> CKRecord.ID {
        guard let recordName = self.recordName else { throw CRUDError.invalidRecordID }
        let recordID = CKRecord.ID(recordName: recordName)
        
        // Get the record if not in cache
        if CKMDefault.getFromCache(recordName) == nil {
            do {
                let record = try await CKMDefault.database.record(for: recordID)
                CKMDefault.addToCache(record)
            } catch {
                // If record doesn't exist, just return the ID
                if (error as? CKError)?.code == .unknownItem {
                    return recordID
                }
                throw error
            }
        }
        
        // Get all references from this record
        let references = CKMDefault.childReferencesInCacheFor(recordName)
        
        // Delete each reference first
        for reference in references {
            do {
                _ = try await CKMDefault.database.deleteRecord(withID: reference.recordID)
            } catch {
                // Skip if already deleted or not found
                if (error as? CKError)?.code != .unknownItem {
                    CKMDefault.logError(error)
                }
            }
        }
        
        // Finally delete the main record
        let deletedRecordID = try await CKMDefault.database.deleteRecord(withID: recordID)
        
        // Remove from cache with cascade to clean up all references
        CKMDefault.removeFromCacheCascade(recordName)
        
        return deletedRecordID
    }
    
    public func ckDeleteCascade(then completion: @escaping (Result<String, Error>) -> Void) {
        guard let recordName = self.recordName else { 
            completion(.failure(CRUDError.invalidRecordID))
            return 
        }
        
        // Use Task to wrap the async implementation
        if #available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *) {
            Task {
                do {
                    let recordID = try await ckDeleteCascadeAsync()
                    completion(.success(recordID.recordName))
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            // Fallback for older OS versions - simple non-cascade delete
            CKMDefault.database.delete(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (_, error) -> Void in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(recordName))
                CKMDefault.removeFromCache(recordName)
            })
        }
    }
	
	public static func load(from record:CKRecord)throws->Self {
		if record.haveCycle() {
			throw CRUDError.circularReferenceDetected(fieldName: "unknown", typeName: Self.ckRecordType)
		} // else
		
		return try Self.load(from: record.asDictionary)
	}
	
	public static func load(from dictionary:[String:Any])throws->Self {
		do {
			// Use the new Codable helpers
			if let customCodable = Self.self as? CKMCustomCodable.Type {
				return try customCodable.ckCustomDecode(from: dictionary) as! Self
			} else {
				return try CKMCodableHelpers.decode(dictionary)
			}
		} catch {
			CKMDefault.logError(error)
			throw CRUDError.cannotMapRecordToObject
		}
	}
	
	// Helper function to sanitize dictionaries for JSON serialization
	private static func sanitizeForJSON(_ dictionary: [String: Any]) -> [String: Any] {
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
				// Copy other values as is if they're JSON serializable
				if JSONSerialization.isValidJSONObject([key: value]) {
					sanitized[key] = value
				} else {
					// If not serializable, convert to string representation
					sanitized[key] = String(describing: value)
				}
			}
		}
		return sanitized
	}
	
	// Helper function to sanitize arrays for JSON serialization
	private static func sanitizeArray(_ array: [Any]) -> [Any] {
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
			} else if value is NSNull {
				return NSNull()
			} else {
				if JSONSerialization.isValidJSONObject([0: value]) {
					return value
				} else {
					return String(describing: value)
				}
			}
		}
	}
	
	public mutating func reloadIgnoringFail(completion: ()->Void) {
        
            guard let recordName = self.recordName else { return }
            DispatchQueue.global().sync {
                var result:Self = self
                CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
                    
                        // else
                    if let record = record {
                        do {
                            CKMDefault.addToCache(record)
                            result = try Self.load(from: record.asDictionary)
                            CKMDefault.semaphore.signal()
                        } catch {}
                    }
                    
                })
                CKMDefault.semaphore.wait()
                self = result
                completion()
            }
        
    }
    
    public mutating func refresh(completion: ()->Void) {
        CKMDefault.removeFromCacheCascade(self.recordName ?? "_")
        self.reloadIgnoringFail(completion: completion)
    }
    
    public func syncRefresh()->Self {
        var refreshedRecord = self
        CKMDefault.removeFromCacheCascade(self.recordName ?? "_")
        refreshedRecord.reloadIgnoringFail(completion: {
            CKMDefault.semaphore.signal()
        })
        CKMDefault.semaphore.wait()
        return refreshedRecord
    }


}


    /// New implementation of CKLoadAll with cursor
extension CKMCloudable {
    ///
    /// # Read all records from a type, limited on *limit* maxRecords.
    /// - Parameters:
    ///   - cursor         : A  *CKQueryOperation.Cursor* for query records next page
    ///   - limit          :  max number of result records, or *CKQueryOperation.maximumResults* if ommited.
    ///
    /// - Returns          :
    ///    - a (records, queryCursor)  in a completion handler where:
    ///
    ///       - records          :  contais a type objects array [T] encapsulated in a [Any]
    ///       - queryCursor  : contains a cursor for next page
    ///
    ///    - or
    ///       - an Error, if something goes wrong.
    public static func ckLoadNext(cursor:CKQueryOperation.Cursor,
                                  limit:Int = CKQueryOperation.maximumResults,
                                  then completion:@escaping (Result<(records:[Any], queryCursor: CKQueryOperation.Cursor? ), Error>)->Void) {
        Self.ckGLoadAll(predicate: NSPredicate(value: true), sortedBy: [], cursor: cursor, limit: limit, then: completion)
    }
    
    ///
    /// # Read all records from a type, limited on *limit* maxRecords.
    /// - Parameters:
    ///   - predicate : A NSPredicate for query constraints
    ///   - sortedBy   :  a array of  SortDescriptors
    ///   - limit          :  max number of result records, or *CKQueryOperation.maximumResults* if ommited.
    ///
    /// - Returns          :
    ///    - a (records, queryCursor)  in a completion handler where:
    ///
    ///       - records          :  contais a type objects array [T] encapsulated in a [Any]
    ///       - queryCursor  : contains a cursor for next page
    ///
    ///    - or
    ///       - an Error, if something goes wrong.
    
    public static func ckLoadAll(predicate:NSPredicate = NSPredicate(value:true),
                                 sortedBy sortKeys:[CKSortDescriptor] = [],
                                 limit:Int = CKQueryOperation.maximumResults,
                                 then completion:@escaping (Result<(records:[Any], queryCursor: CKQueryOperation.Cursor? ), Error>)->Void) {
        Self.ckGLoadAll(predicate: predicate, sortedBy: sortKeys, cursor: nil, limit: limit, then: completion)
    }
    
    private static func ckGLoadAll(predicate:NSPredicate = NSPredicate(value:true),
                                   sortedBy sortKeys:[CKSortDescriptor] = [],
                                   cursor:CKQueryOperation.Cursor? = nil,
                                   limit:Int = CKQueryOperation.maximumResults,
                                   then completion:@escaping (Result<(records:[Any], queryCursor: CKQueryOperation.Cursor? ), Error>)->Void) {
        
            var records:[Self] = []
            var ckRecords:[CKRecord] = []
                //Prepare the query
            
            let operation:CKQueryOperation = {
                if let cursor { return CKQueryOperation(cursor: cursor)}
                    // else
                let query = CKQuery(recordType: Self.ckRecordType, predicate: predicate)
                query.sortDescriptors = sortKeys.ckSortDescriptors
                return CKQueryOperation(query: query)
            }()
            operation.resultsLimit = limit
            
            
            operation.recordFetchedBlock = {record in
                ckRecords.append(record)
                if let item = try? Self.load(from: record.asDictionary) {
                    records.append(item)
                }
            }
            
            operation.queryCompletionBlock = { cursor, error in
                
                if let error { completion(.failure(error)) } else {
                    
                        // If not all records were mapped, completion will be called twice: failure + mapped records
                    guard ckRecords.count == records.count else {
                        completion(.failure(CRUDError.cannotMapAllRecords))
                        if records.count > 0 {
                            completion(.success((records:ckRecords, queryCursor:cursor)))
                        }
                        return
                    } // end guard
                    
                    CKMDefault.addToCache(ckRecords)
                    completion(.success((records:records, queryCursor:cursor)))
                }
                
            }
                // Run operation
            CKMDefault.database.add(operation)
        
    }
    
    @available(watchOS 6.0.0, *)
    @available(iOS 15.0, *)
    private static func ckGLoadAll(predicate: NSPredicate = NSPredicate(value: true),
                                   sortedBy sortKeys: [CKSortDescriptor] = [],
                                   cursor: CKQueryOperation.Cursor? = nil,
                                   limit: Int = CKQueryOperation.maximumResults) async -> CKMRecordAsyncResult {
        
        var records: [Self] = []
        var ckRecords: [CKRecord] = []
        var ckErrors: [CKMRecordName: Error] = [:]
        //Prepare the query
        
        let query = CKQuery(recordType: Self.ckRecordType, predicate: predicate)
        query.sortDescriptors = sortKeys.ckSortDescriptors
        
        do {
            var result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                if #available(watchOS 8.0, *) {
                    result = try await CKMDefault.database.records(continuingMatchFrom: cursor)
                } else {
                    // Fallback on earlier versions
                    // Initialize with empty values for older OS versions
                    result = (matchResults: [], queryCursor: nil)
                    throw CRUDError.invalidRecord
                }
            } else {
                if #available(watchOS 8.0, *) {
                    result = try await CKMDefault.database.records(matching: query, resultsLimit: limit)
                } else {
                    // Fallback on earlier versions
                    // Initialize with empty values for older OS versions
                    result = (matchResults: [], queryCursor: nil)
                    throw CRUDError.invalidRecord
                }
            }
            
            result.matchResults.forEach { matchResult in
                switch matchResult.1 {
                    case .success(let ckRecord):
                        ckRecords.append(ckRecord)
                        do {
                            let item = try Self.load(from: ckRecord.asDictionary)
                            records.append(item)
                        } catch {
                            ckErrors[matchResult.0.recordName] = error
                        }
                    case .failure(let error):
                        ckErrors[matchResult.0.recordName] = error
                }
            }
            
            CKMDefault.addToCache(ckRecords)
            
            return .success((records: records, queryCursor: result.queryCursor, partialErrors: ckErrors))
            
        } catch {
            return .failure(error)
        }
    }
}

@available(watchOS 6.0.0, *)
@available(iOS 15.0, *)
extension CKMCloudable {
    @available(watchOS 6.0.0, *)
    @available(iOS 15.0, *)
    public static func ckLoadNext(cursor: CKQueryOperation.Cursor,
                                  limit: Int = CKQueryOperation.maximumResults) async -> CKMRecordAsyncResult {
        return await Self.ckGLoadAll(predicate: NSPredicate(value: true), sortedBy: [], cursor: cursor, limit: limit)
    }
    
        ///
        /// # Read all records from a type, limited on *limit* maxRecords.
        /// - Parameters:
        ///   - predicate : A NSPredicate for query constraints
        ///   - sortedBy   :  a array of  SortDescriptors
        ///   - limit          :  max number of result records, or *CKQueryOperation.maximumResults* if ommited.
        ///
        /// - Returns          :
        ///    - a (records, queryCursor)  in a completion handler where:
        ///
        ///       - records          :  contais a type objects array [T] encapsulated in a [Any]
        ///       - queryCursor  : contains a cursor for next page
        ///
        ///    - or
        ///       - an Error, if something goes wrong.
    
    @available(watchOS 6.0.0, *)
    @available(iOS 15.0, *)
    public static func ckLoadAll(predicate: NSPredicate = NSPredicate(value: true),
                                 sortedBy sortKeys:[CKSortDescriptor] = [],
                                 limit: Int = CKQueryOperation.maximumResults) async -> CKMRecordAsyncResult {
        
        
        var stillQuerying = true
        var cursor: CKMCursor? = nil
        
        var allRecords: [Self] = []
        var allPartialErrors: [CKMRecordName:Error] = [:]
        
        while stillQuerying {
            
            let result = await Self.ckGLoadAll(predicate: predicate, sortedBy: sortKeys, cursor: cursor, limit: limit)
            
            switch result {
                case .success(let (records, queryCursor, partialErrors)):
                    if let records = records as? [Self] {
                        allRecords.append(contentsOf: records)
                    }
                    allPartialErrors.merge(partialErrors) { (current, _) in current }
                    cursor = queryCursor
                    stillQuerying = cursor != nil
                    
                case .failure(let error):
                    stillQuerying = false
                    return .failure(error)
            }
        }
        
        
        
        let finalAsyncResult: CKMRecordAsyncResult = .success((records: allRecords, queryCursor: nil, partialErrors: allPartialErrors))
        
        return finalAsyncResult
    }
    @available(watchOS 8.0, *)
    @available(iOS 15.0, *)
    public func ckSave() async throws -> Self {
            let ckPreparedRecord = try await self.prepareCKRecordAsync()
            let record           = try await CKMDefault.database.save(ckPreparedRecord.record)
            let finalRecord      = try await ckPreparedRecord.dispatchPendingAsync(for: record)
            let object           = try       Self.load(from: finalRecord.asDictionary)
        return object
    }
    
    @available(watchOS 6.0.0, *)
    @available(iOS 15.0, *)
    public static func ckLoad(with recordName: String) async throws -> Self {
        
                // Try to get from cache
            if let record = CKMDefault.getFromCache(recordName) {
                do {
                        //                let result:Self = try Self.ckLoad(from: record)
                    let result:Self = try Self.load(from: record.asDictionary)
                    return result
                } catch {
                    
                    throw CRUDError.cannotMapRecordToObject
                }
            }
            
            let record = try await CKMDefault.database.record(for: CKRecord.ID(recordName: recordName))
            
            do {
                CKMDefault.addToCache(record)
                let result: Self = try Self.load(from: record)
                return result
            } catch {
                CKMDefault.removeFromCache(record.recordID.recordName)
                throw CRUDError.cannotMapRecordToObject
            }
                // else get from database
            
        
    }
    
    @available(watchOS 6.0.0, *)
    public func ckDelete() async throws -> CKRecord.ID {
        guard let recordName = self.recordName else { throw CRUDError.invalidRecordID }
        
        let recordID = try await CKMDefault.database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
        CKMDefault.removeFromCache(recordName)
        return recordID
       
    }
    
}

// MARK: - Explicit Update vs Insert Operations
@available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
extension CKMCloudable {
    
    /// Explicitly creates a new record in CloudKit.
    /// This method will fail if a record with the same ID already exists.
    /// - Returns: The saved object with updated metadata
    /// - Throws: CRUDError.recordExists if a record with the same ID already exists
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func ckInsertAsync() async throws -> Self {
        do {
            // Check if record already exists
            if self.recordName != nil {
                throw CRUDError.recordAlreadyExists(recordName: self.recordName ?? "unknown", typeName: Self.ckRecordType)
            }
            
            // Prepare record
            let preparedRecord = try await self.prepareCKRecordAsync()
            
            // Save record
            let record = try await CKMDefault.database.save(preparedRecord.record)
            let finalRecord = try await preparedRecord.dispatchPendingAsync(for: record)
            let object = try Self.load(from: finalRecord.asDictionary)
            return object
        } catch {
            CKMDefault.logError(error)
            throw error
        }
    }
    
    /// Explicitly updates an existing record in CloudKit.
    /// This method will fail if a record with the specified ID doesn't exist.
    /// - Returns: The updated object with refreshed metadata
    /// - Throws: CRUDError.recordNotFound if no record with the specified ID exists
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func ckUpdateAsync() async throws -> Self {
        do {
            // Check if record exists
            guard self.recordName != nil else {
                throw CRUDError.recordDoesNotExist(recordName: "nil", typeName: Self.ckRecordType)
            }
            
            // Prepare record
            let preparedRecord = try await self.prepareCKRecordAsync()
            
            // Save record
            let record = try await CKMDefault.database.save(preparedRecord.record)
            let finalRecord = try await preparedRecord.dispatchPendingAsync(for: record)
            let object = try Self.load(from: finalRecord.asDictionary)
            return object
        } catch {
            CKMDefault.logError(error)
            throw error
        }
    }
    
    /// Saves a record to CloudKit, creating it if it doesn't exist or updating it if it does.
    /// This is a safer alternative to ckSave() that provides better error handling.
    /// - Returns: The saved object with updated metadata
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func ckUpsertAsync() async throws -> Self {
        if let recordName = self.recordName {
            do {
                // Try to fetch the record to see if it exists
                _ = try await CKMDefault.database.record(for: CKRecord.ID(recordName: recordName))
                // Record exists, perform update
                return try await ckUpdateAsync()
            } catch let error as CKError where error.code == .unknownItem {
                // Record doesn't exist, perform insert
                return try await ckInsertAsync()
            } catch {
                // Other error occurred during fetch
                throw CRUDError.operationFailed(operation: "upsert-check", typeName: Self.ckRecordType, underlyingError: error)
            }
        } else {
            // No recordName, must be a new record
            return try await ckInsertAsync()
        }
    }
    
    // Helper method to process a field for CloudKit record
    private func processField(_ field: Mirror.Child, into ckRecord: CKRecord, preparedRecord: CKMPreparedRecord) async throws {
        var value = field.value
        guard !"\(value)".elementsEqual("nil") else { return } // Skip nil values
        
        guard let key = field.label else {
            throw CRUDError.invalidField(fieldName: "unknown", typeName: Self.ckRecordType, message: "Field without label")
        }
        
        // Skip system fields
        if field.label?.elementsEqual("recordName") ?? false
            || field.label?.elementsEqual("createdBy") ?? false
            || field.label?.elementsEqual("createdAt") ?? false
            || field.label?.elementsEqual("modifiedBy") ?? false
            || field.label?.elementsEqual("modifiedAt") ?? false
            || field.label?.elementsEqual("changeTag") ?? false {
            return
        }
        
        // Handle basic types (Number, String, Date, or arrays of these elements)
        if isBasicType(field.value) {
            ckRecord.setValue(value, forKey: key)
        }
        // Handle Data or [Data], convert to Asset or [Asset]
        else if let data = value as? Data {
            value = CKAsset(data: data)
            ckRecord.setValue(value, forKey: key)
        }
        else if let datas = value as? [Data] {
            value = datas.map { CKAsset(data: $0) }
            ckRecord.setValue(value, forKey: key)
        }
        // Handle CKCloudable references
        else if let value = (field.value as AnyObject) as? CKMCloudable {
            // If reference has recordName, use it
            if let reference = value.referenceInCacheOrNull {
                ckRecord.setValue(reference, forKey: key)
            }
            // If this record has a recordName, save the dependency
            else if self.recordName != nil {
                do {
                    if let reference = try await value.referenceSavingRecordIfNullAsync() {
                        ckRecord.setValue(reference, forKey: key)
                    } else {
                        throw CRUDError.invalidReference(fieldName: key, typeName: Self.ckRecordType)
                    }
                } catch let error {
                    throw CRUDError.referenceSavingFailed(fieldName: key, typeName: Self.ckRecordType, underlyingError: error)
                }
            }
            // If this record doesn't have a recordName and has a cyclic reference, store for later
            else if value.haveCycle(with: self) {
                preparedRecord.add(value: value, forKey: key)
            }
        }
        // Handle arrays of CKCloudable
        else if let value = field.value as? [CKMCloudable] {
            var references: [CKRecord.Reference] = []
            for (index, item) in value.enumerated() {
                do {
                    if let reference = try await item.referenceSavingRecordIfNullAsync() {
                        references.append(reference)
                    } else {
                        throw CRUDError.invalidReference(fieldName: "\(key)[\(index)]", typeName: Self.ckRecordType)
                    }
                } catch let error {
                    throw CRUDError.referenceSavingFailed(fieldName: "\(key)[\(index)]", typeName: Self.ckRecordType, underlyingError: error)
                }
            }
            ckRecord.setValue(references, forKey: key)
        }
        // Handle unsupported types
        else {
            throw CRUDError.invalidField(fieldName: key, typeName: Self.ckRecordType, message: "Unsupported type: \(type(of: field.value))")
        }
    }
}

@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
extension CKMCloudable {
    /**
    Read all records from a type
    - Parameters:
    - sortedBy a array of  SortDescriptors
    - returns: a (Result<Any, Error>) where Any contais a type objects array [T] in a completion handler
    */
    @available(*, deprecated, message: "Use the new version with custom limit and cursor")
    public static func ckLoadAll(sortedBy sortKeys:[CKSortDescriptor] = [], predicate:NSPredicate = NSPredicate(value:true), then completion:@escaping (Result<Any, Error>)->Void) {
        
                //Prepare the query
            let query = CKQuery(recordType: Self.ckRecordType, predicate: predicate)
            query.sortDescriptors = sortKeys.ckSortDescriptors
            
            
                // Execute the query
            CKMDefault.database.perform(query, inZoneWith: nil, completionHandler: { (records, error) -> Void in
                
                    // Got error
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                    // else
                if let records = records {
                    let result:[Self] = records.compactMap{
                        let dictionary = $0.asDictionary
                        
                        return try? Self.load(from: dictionary)}
                    
                    guard records.count == result.count else {
                        completion(.failure(CRUDError.cannotMapAllRecords))
                        return
                    }
                    CKMDefault.addToCache(records)
                    completion(.success(result))
                }
                
            })
        
    }
    
    /**
    Read all records from a type
    - Parameters:
    - recordName an iCloud recordName id for fetch
    - returns: a (Result<Any, Error>) where Any contais a CKMRecord type object  in a completion handler
    */
    public static func ckLoad(with recordName: String , then completion:@escaping (Result<Any, Error>)->Void) {
        
                // Try to get from cache
            
                // try get from cache
            if let record = CKMDefault.getFromCache(recordName) {
                do {
                        //				let result:Self = try Self.ckLoad(from: record)
                    let result:Self = try Self.load(from: record.asDictionary)
                    completion(.success(result))
                } catch {
                    completion(.failure(CRUDError.cannotMapRecordToObject))
                    return
                }
            }
            
                // else get from database
            CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
                
                    // Got error
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                
                    // else
                if let record = record {
                    do {
                        CKMDefault.addToCache(record)
                        let result:Self = try Self.load(from: record)
                        completion(.success(result))
                        return
                    } catch {
                        CKMDefault.removeFromCache(record.recordID.recordName)
                        completion(.failure(CRUDError.cannotMapRecordToObject))
                        return
                    }
                } else {
                    completion(.failure(CRUDError.noSurchRecord))
                }
                
            })
        
    }
    
    @available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
    public static func ckLoadAsync(with recordName: String) async throws -> Self {
        if let record = CKMDefault.getFromCache(recordName) {
            return try Self.load(from: record.asDictionary)
        }
        
        let record = try await CKMDefault.database.record(for: CKRecord.ID(recordName: recordName))
        CKMDefault.addToCache(record)
        return try Self.load(from: record.asDictionary)
    }
}

@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
extension CKMCloudable {
    // This extension intentionally left empty
}
