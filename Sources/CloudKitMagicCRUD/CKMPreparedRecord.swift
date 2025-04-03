//
//  CKMPreparedRecord.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 20/08/20.
//  Copyright 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

import CloudKit

/// Class for handling CloudKit records with cyclic references
@available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
open class CKMPreparedRecord {
	/// List of pending references that need to be saved
	open var pending:[CKMPreparedRecord.Reference] = []
	/// The CloudKit object being saved
	open var objectSaving:CKMCloudable
	/// The CloudKit record being prepared
	open var record:CKRecord
	
	/// Checks if all pending references have been filled
	open var allPendingValuesFilled:Bool {
		for item in pending {
			guard let _ = record.value(forKey: item.pendingCyclicReferenceName) else {return false}
		}
		return true
	}

	/// Initializes a prepared record with an object and its CloudKit record
	public init(for objectSaving:CKMCloudable, in record:CKRecord) {
		self.objectSaving = objectSaving
		self.record = record
	}
	
	/// Class representing a reference to another object that needs to be saved
	open class Reference {
		/// The object that needs to be saved before the parent
		open var cyclicReferenceBranch:CKMCloudable
		/// The field name where the reference will be stored
		open var pendingCyclicReferenceName:String

		/// Initializes a reference with an object and field name
		public init(value cyclicReferenceBranch:CKMCloudable,
			 forKey pendingCyclicReferenceName:String) {
			self.cyclicReferenceBranch = cyclicReferenceBranch
			self.pendingCyclicReferenceName = pendingCyclicReferenceName
			
		}
	}
	
	
	/// Adds a new pending reference to be resolved
	open func add(value cyclicReferenceBranch:CKMCloudable, forKey pendingCyclicReferenceName:String) {
		let new = CKMPreparedRecord.Reference(value: cyclicReferenceBranch, forKey: pendingCyclicReferenceName)
		pending.append(new)
	}
	
    /// Resolves pending references after the main record has been saved
    @available(watchOS 8.0, *)
    open func dispatchPending(for savedRecord:CKRecord, then completion:@escaping (Result<CKRecord, Error>)->Void) {
		// Update self with saved record
		self.record = savedRecord
		self.objectSaving.recordName = record.recordID.recordName
		CKMDefault.addToCache(record)
		
		// Verify that the record has a valid recordName
		guard let _ = objectSaving.recordName else {
			debugPrint("Cannot dispatch pending without a saved Record")
			debugPrint("Object \(objectSaving) must have a recordName")
			return
		}
		
		// Check if there are pending references
		guard !pending.isEmpty else {
			completion(.success(record))
			return
		}
		
		// If there are pending references
		for item in pending {
			// Save each pending reference
			item.cyclicReferenceBranch.ckSave(then: { result in
				switch result {
					case .success(let savedBranchRecord):
						guard let referenceID = (savedBranchRecord as? CKMCloudable)?.recordName else {
							debugPrint("Error saving reference object for \(item.pendingCyclicReferenceName) in \(self.record.recordType) - Record saved without reference")
							dump(self.record)
							return
						}
						// Update the record with the saved reference
						self.updateRecord(with: referenceID, in: item, then: completion)
					case .failure(let error):
						debugPrint("Error saving reference object for \(item.pendingCyclicReferenceName) in \(self.record.recordType)")
						dump(error)
				}
			})
		}
	}
	
	/// Updates the record with a reference to another saved object
	open func updateRecord(with reference: String, in item: CKMPreparedRecord.Reference, then completion:@escaping (Result<CKRecord, Error>)->Void) {
		let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: reference), action: .none)
		let referenceField = item.pendingCyclicReferenceName
		// If the field is an array of references
		if var referenceArray = self.record.value(forKey: referenceField) as? [CKRecord.Reference] {
			referenceArray.append(reference)
			self.record.setValue(referenceArray, forKey: referenceField)
		}
		// If the field is a single reference
		else {
			self.record.setValue(reference, forKey: referenceField)
		}
		
		// If all pending references have been filled
		if self.allPendingValuesFilled {
			// Update the record in the database and complete with the result
			CKMDefault.database.save(self.record, completionHandler: {
				(record,error) -> Void in
				
				// If there was an error
				if let error = error {
					completion(.failure(error))
				}
				// If the record was saved successfully
				else if let record = record {
					CKMDefault.addToCache(record)
					completion(.success(record))
				}
			})
		}

	}
	
    /// Async version of dispatchPending
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func dispatchPendingAsync(for savedRecord: CKRecord) async throws -> CKRecord {
        self.record = savedRecord
        self.objectSaving.recordName = record.recordID.recordName
        CKMDefault.addToCache(record)
        
        guard let _ = objectSaving.recordName else {
            let errorMessage = "Object \(objectSaving) must have a recordName"
            CKMDefault.logError(NSError(domain: "CKMPreparedRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            throw NSError(domain: "CKMPreparedRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        guard !pending.isEmpty else { return record }
        
        for item in pending {
            let savedBranchRecord = try await item.cyclicReferenceBranch.ckSave()
            
            guard let referenceID = savedBranchRecord.recordName else {
                let errorMessage = "\(item.pendingCyclicReferenceName) in \(self.record.recordType) - Record saved without reference"
                CKMDefault.logError(NSError(domain: "CKMPreparedRecord", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                throw NSError(domain: "CKMPreparedRecord", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            if let ckRecord = try await self.updateRecordAsync(with: referenceID, in: item) {
                return ckRecord
            }
        }
        return self.record
    }
    
    /// Async version of updateRecord
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public func updateRecordAsync(with reference: String, in item: CKMPreparedRecord.Reference) async throws -> CKRecord? {
        let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: reference), action: .none)
        let referenceField = item.pendingCyclicReferenceName
        // If the field is an array of references
        if var referenceArray = self.record.value(forKey: referenceField) as? [CKRecord.Reference] {
            referenceArray.append(reference)
            self.record.setValue(referenceArray, forKey: referenceField)
        } else {
            // If the field is a single reference
            self.record.setValue(reference, forKey: referenceField)
        }
        
        if self.allPendingValuesFilled {
            let record = try await CKMDefault.database.save(self.record)
            CKMDefault.addToCache(record)
            return record
        }
        return nil
    }
    
    /// Error enum for prepare record operations
    public enum PrepareRecordErrors: Error {
        case cannotDispatchPendingWithoutSavedRecord(String)
        case errorSavingReferenceObject(String)
    }
}
