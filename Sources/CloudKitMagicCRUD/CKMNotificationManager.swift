//
//  CKMNotificationManager.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 18/08/20.
//  Copyright 2020 Ricardo Venieris. All rights reserved.
//
//  Modified by MDavid Low on 04/2025
//

// iOS, tvOS, and watchOS
#if canImport(UIKit)
import UIKit
import CloudKit
import UserNotifications
import Combine

/// Manages CloudKit notifications and subscriptions
open class CKMNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    /// Dictionary mapping record types to their observers
	open var observers: [CKRecord.RecordType: NSPointerArray] = [:]
    
    /// Shared instance of the notification manager
    public static var shared = { CKMNotificationManager() }()
    
    /// Publisher that emits notifications when they are received
    @available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
    public static let receivedNotificationPublisher = PassthroughSubject<CKMNotification, Never>()
    
	private override init() {
		super.init()
		self.registerInNotificationCenter()
	}
	
    /// Registers the manager with the notification center and requests authorization
	open func registerInNotificationCenter() {
		UNUserNotificationCenter.current().delegate = self
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { authorized, error in
			if authorized {
				DispatchQueue.main.async {
					// let app = UIApplication.shared.delegate as! AppDelegate
#if os(iOS) || targetEnvironment(macCatalyst)
                    UIApplication.shared.registerForRemoteNotifications()
#endif
				}
			}
		})
	}
    
    /// Handles incoming CloudKit notifications
    @available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
    public static func notificationHandler(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any]
        let category = aps?["category"] as? String

        let ck = userInfo["ck"] as? [AnyHashable: Any]
        let userID = ck?["ckuserid"] as? String
        let qry = ck?["qry"] as? [AnyHashable: Any]
        let recordID = qry?["rid"] as? String
        let subscriptionID = qry?["sid"] as? String
        let zoneID = qry?["zid"] as? String
                
        Self.receivedNotificationPublisher.send(CKMNotification(
            category: category ?? "unknown",
            recordID: recordID,
            subscriptionID: subscriptionID,
            zoneID: zoneID,
            userID: userID,
            date: Date(),
            identifier: "",
            title: "",
            subtitle: "",
            body: "",
            badge: nil,
            sound: nil,
            launchImageName: ""
        ))
    }
    
    /// Creates a notification subscription for a specific record type
    @available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *)
    open func createNotification<T: CKMCloudable>(
        to recordObserver: CKMRecordObserver,
        for recordType: T.Type,
        options: CKQuerySubscription.Options? = nil,
        predicate: NSPredicate? = nil,
        alertBody: String? = nil,
        completion: @escaping (Result<CKSubscription, Error>) -> Void
    ) {
#if !os(tvOS)
		let options = options ?? [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
		let predicate = predicate ?? NSPredicate(value: true)
		
		let info = CKSubscription.NotificationInfo()
		info.alertBody = alertBody
		info.category = recordType.ckRecordType
		info.shouldSendContentAvailable = true
		info.shouldSendMutableContent = true
		
		let subscription = CKQuerySubscription(recordType: recordType.ckRecordType, predicate: predicate, options: options)
		subscription.notificationInfo = info
		
		self.add(observer: recordObserver, to: recordType.ckRecordType)
		
        // Create a local copy of the predicate to avoid Sendable issues
        let predicateString = predicate.predicateFormat
        
        // Check for existing subscriptions before creating a new one
        CKMDefault.database.fetchAllSubscriptions { [weak self] subscriptions, error in
            if self == nil { return }
            
            if let error = error {
                // If we can't fetch subscriptions, try to save anyway
                CKMDefault.logError(error)
                CKMDefault.database.save(subscription) { savedSubscription, saveError in
                    if let savedSubscription = savedSubscription {
                        completion(.success(savedSubscription))
                    } else if let saveError = saveError {
                        CKMDefault.logError(saveError)
                        completion(.failure(saveError))
                    }
                }
                return
            }
            
            if let subscriptions = subscriptions {
                // Check if a subscription with the same record type and predicate already exists
                let existingSubscription = subscriptions.first { sub in
                    guard let querySub = sub as? CKQuerySubscription else { return false }
                    // Compare record type and predicate string instead of the predicate object
                    if querySub.recordType != recordType.ckRecordType {
                        return false
                    }
                    
                    // Compare predicate strings
                    return querySub.predicate.predicateFormat == predicateString
                }
                
                if let existing = existingSubscription {
                    // Subscription already exists, return it
                    completion(.success(existing))
                } else {
                    // Create a new subscription
                    CKMDefault.database.save(subscription) { savedSubscription, error in
                        if let savedSubscription = savedSubscription {
                            completion(.success(savedSubscription))
                        } else if let error = error {
                            CKMDefault.logError(error)
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
#endif
	}
    
    /// Async version of createNotification
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    open func createNotificationAsync<T: CKMCloudable>(
        to recordObserver: CKMRecordObserver,
        for recordType: T.Type,
        options: CKQuerySubscription.Options? = nil,
        predicate: NSPredicate? = nil,
        alertBody: String? = nil
    ) async throws -> CKSubscription {
#if !os(tvOS)
        let options = options ?? [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        let predicate = predicate ?? NSPredicate(value: true)
        
        let info = CKSubscription.NotificationInfo()
        info.alertBody = alertBody
        info.category = recordType.ckRecordType
        info.shouldSendContentAvailable = true
        info.shouldSendMutableContent = true
        
        let subscription = CKQuerySubscription(recordType: recordType.ckRecordType, predicate: predicate, options: options)
        subscription.notificationInfo = info
        
        self.add(observer: recordObserver, to: recordType.ckRecordType)
        
        // Create a local copy of the predicate to avoid Sendable issues
        let predicateString = predicate.predicateFormat
        let recordTypeString = recordType.ckRecordType
        
        // Check for existing subscriptions using continuation pattern
        return try await withCheckedThrowingContinuation { continuation in
            CKMDefault.database.fetchAllSubscriptions { subscriptions, error in
                if let error = error {
                    // If we can't fetch subscriptions, try to save anyway
                    CKMDefault.logError(error)
                    CKMDefault.database.save(subscription) { savedSubscription, saveError in
                        if let savedSubscription = savedSubscription {
                            continuation.resume(returning: savedSubscription)
                        } else if let saveError = saveError {
                            CKMDefault.logError(saveError)
                            continuation.resume(throwing: saveError)
                        } else {
                            continuation.resume(throwing: NSError(domain: "CKMNotificationManager", code: 3,
                                                                 userInfo: [NSLocalizedDescriptionKey: "Unknown error saving subscription"]))
                        }
                    }
                    return
                }
                
                if let subscriptions = subscriptions {
                    // Check if a subscription with the same record type and predicate already exists
                    let existingSubscription = subscriptions.first { sub in
                        guard let querySub = sub as? CKQuerySubscription else { return false }
                        // Compare record type and predicate string instead of the predicate object
                        if querySub.recordType != recordTypeString {
                            return false
                        }
                        
                        // Compare predicate strings
                        return querySub.predicate.predicateFormat == predicateString
                    }
                    
                    if let existing = existingSubscription {
                        // Subscription already exists, return it
                        continuation.resume(returning: existing)
                    } else {
                        // Create a new subscription
                        CKMDefault.database.save(subscription) { savedSubscription, saveError in
                            if let savedSubscription = savedSubscription {
                                continuation.resume(returning: savedSubscription)
                            } else if let saveError = saveError {
                                CKMDefault.logError(saveError)
                                continuation.resume(throwing: saveError)
                            } else {
                                continuation.resume(throwing: NSError(domain: "CKMNotificationManager", code: 3,
                                                                     userInfo: [NSLocalizedDescriptionKey: "Unknown error saving subscription"]))
                            }
                        }
                    }
                } else {
                    // No subscriptions returned but no error either, try to save
                    CKMDefault.database.save(subscription) { savedSubscription, saveError in
                        if let savedSubscription = savedSubscription {
                            continuation.resume(returning: savedSubscription)
                        } else if let saveError = saveError {
                            CKMDefault.logError(saveError)
                            continuation.resume(throwing: saveError)
                        } else {
                            continuation.resume(throwing: NSError(domain: "CKMNotificationManager", code: 3,
                                                                 userInfo: [NSLocalizedDescriptionKey: "Unknown error saving subscription"]))
                        }
                    }
                }
            }
        }
#else
        throw NSError(domain: "CKMNotificationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Notifications not supported on tvOS"])
#endif
    }
    
    /// Deletes a subscription with the given ID
    open func deleteSubscription(with id: CKSubscription.ID, then completion: @escaping (Result<String, Error>) -> Void) {
        if #available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *) {
            CKMDefault.database.delete(withSubscriptionID: id) { message, error in
                if let message = message {
                    completion(.success(message))
                } else if let error = error {
                    CKMDefault.logError(error)
                    completion(.failure(error))
                }
            }
        } else {
            // Fallback for earlier versions
            let error = NSError(domain: "CKMNotificationManager", code: 1, 
                               userInfo: [NSLocalizedDescriptionKey: "Deleting subscriptions requires iOS 13+"])
            completion(.failure(error))
        }
    }
    
    /// Async version of deleteSubscription
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    open func deleteSubscriptionAsync(with id: CKSubscription.ID) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            CKMDefault.database.delete(withSubscriptionID: id) { message, error in
                if let message = message {
                    continuation.resume(returning: message)
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NSError(domain: "CKMNotificationManager", code: 2,
                                                         userInfo: [NSLocalizedDescriptionKey: "Unknown error deleting subscription"]))
                }
            }
        }
    }
    
    /// Adds an observer for a specific record type
	private func add(observer: CKMRecordObserver, to identifier: String) {
		self.observers[identifier] = self.observers[identifier] ?? NSPointerArray.strongObjects()
		self.observers[identifier]?.addObject(observer as AnyObject)
	}
	
    /// Notifies observers when a notification is received
	open func notifyObserversFor(_ notification: UNNotification) {
#if !os(tvOS)
		let recordTypeName = notification.request.content.categoryIdentifier
        
		self.observers.forEach { $0.value.compact() }
		let interestedObservers = observers.filter { $0.key == recordTypeName }
		for observers in interestedObservers {
			for observer in observers.value.allObjects {
                (observer as? CKMRecordObserver)?.onReceive(notification: CKMNotification(from: notification))
			}
		}
#endif
	}
	
    /// Called when a notification will be presented
	open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
		completionHandler([]) // Use [] for silent notifications, or [.alert, .sound, .badge] for visible ones
		notifyObserversFor(notification)
	}

    /// Called when the user responds to a notification
    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        notifyObserversFor(response.notification)
        completionHandler()
    }
}

/**
 A simplified representation of a CloudKit notification
 
 - Parameters:
    - category: The category of the notification, usually a record type name
    - recordID: The record ID of the record that triggered the notification
    - subscriptionID: The ID of the subscription that was triggered
    - zoneID: The zone ID of the subscription that triggered the notification
    - userID: The user that made the changes
    - date: The delivery date of the notification
    - identifier: The unique identifier for this notification request
    - title: A short description of the reason for the alert
    - subtitle: A secondary description of the reason for the alert
    - body: The message displayed in the notification alert
    - badge: The number to display as the app's icon badge
    - sound: The sound to play when the notification is delivered
    - launchImageName: The name of the launch image to display when your app is launched in response to the notification
 */
open class CKMNotification {
    public let category: String
    public let recordID: String?
    public let subscriptionID: String?
    public let zoneID: String?
    public let userID: String?
    public let date: Date
    public let identifier: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let badge: NSNumber?
#if !os(tvOS)
    public let sound: UNNotificationSound?
#endif
    public let launchImageName: String
    
    /// Creates a notification from a UNNotification
    public init(from notification: UNNotification) {
#if !os(tvOS)
        self.category = notification.request.content.categoryIdentifier
        self.date = notification.date
        self.identifier = notification.request.identifier
        self.title = notification.request.content.title
        self.subtitle = notification.request.content.subtitle
        self.body = notification.request.content.body
        self.badge = notification.request.content.badge
        self.sound = notification.request.content.sound
        self.launchImageName = notification.request.content.launchImageName
        
        let userInfo = notification.request.content.userInfo
        
        let ck = userInfo["ck"] as? [AnyHashable: Any]
        self.userID = ck?["ckuserid"] as? String
        
        let qry = ck?["qry"] as? [AnyHashable: Any]
        self.recordID = qry?["rid"] as? String
        self.subscriptionID = qry?["sid"] as? String
        self.zoneID = qry?["zid"] as? String
#else
        self.date = Date()
        self.identifier = ""
        self.title = ""
        self.subtitle = ""
        self.body = ""
        self.category = ""
        self.launchImageName = ""
        self.recordID = nil
        self.subscriptionID = nil
        self.zoneID = nil
        self.userID = nil
        self.badge = nil
#endif
    }
    
    /// Creates a notification with the specified parameters
    public init(
        category: String,
        recordID: String? = nil,
        subscriptionID: String? = nil,
        zoneID: String? = nil,
        userID: String? = nil,
        date: Date,
        identifier: String,
        title: String,
        subtitle: String,
        body: String,
        badge: NSNumber? = nil,
        sound: UNNotificationSound? = nil,
        launchImageName: String
    ) {
        self.category = category
        self.recordID = recordID
        self.subscriptionID = subscriptionID
        self.zoneID = zoneID
        self.userID = userID
        self.date = date
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
#if !os(tvOS)
        self.sound = sound
#endif
        self.launchImageName = launchImageName
    }
}

/// Extension to register observers for CloudKit record changes
extension CKMCloudable {
    /// Registers an observer for changes to this record type
    public static func register(observer: CKMRecordObserver) {
        if #available(iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0, *) {
            CKMDefault.notificationManager.createNotification(
                to: observer,
                for: Self.self,
                completion: { result in
                    switch result {
                    case .success:
                        debugPrint("Successfully registered observer for \(Self.ckRecordType)")
                    case .failure(let error):
                        CKMDefault.logError(error)
                    }
                }
            )
        }
    }
    
    /// Registers an observer for changes to this record type (async version)
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    public static func registerAsync(observer: CKMRecordObserver) async throws {
        _ = try await CKMDefault.notificationManager.createNotificationAsync(
            to: observer,
            for: Self.self
        )
    }
}

/// Protocol for CloudKit notification observers
public protocol CKMRecordObserver: AnyObject {
    /// Called when a notification is received for a record
    func onReceive(notification: CKMNotification)
}

/// Extension to provide access to the notification manager
extension CKMDefault {
    /// The shared notification manager instance
    public static var notificationManager: CKMNotificationManager! = CKMNotificationManager.shared
}

#endif
