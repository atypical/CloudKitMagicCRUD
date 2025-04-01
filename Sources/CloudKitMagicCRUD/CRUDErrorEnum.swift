//
//  Enums.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

import Foundation


public enum CRUDError:Int, Error {
	case invalidRecord
	case invalidRecordID
	case cannotMapAllRecords
	case cannotDeleteRecord
	case cannotMapRecordToObject
	case noSurchRecord
	case needToSaveRefferencedRecord
	case invalidFieldType_Dictionary
	
}

