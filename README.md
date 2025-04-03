# CloudKitMagicCRUD

Forked from [rvenieris/CloudKitMagicCRUD](https://github.com/rvenieris/CloudKitMagicCRUD)

## Overview

CloudKitMagicCRUD is a Swift package that simplifies working with CloudKit, Apple's cloud-based backend service. It provides a set of APIs and tools to make it easier to interact with CloudKit, including support for async/await, caching, and error handling.

## Features

* **Async/Await Support**: CloudKitMagicCRUD provides async/await methods for all CloudKit operations, making it easier to write asynchronous code.
* **Caching**: The package includes a built-in caching system to improve performance and reduce the number of requests made to CloudKit.
* **Error Handling**: CloudKitMagicCRUD provides enhanced error handling with detailed information about which field caused an issue.
* **Explicit Record Operations**: The package provides explicit methods for different record operations, such as insert, update, and upsert.
* **Custom Codable Implementation**: You can customize how your models are encoded and decoded by conforming to `CKMCustomCodable`.
* **Handling References Between Objects**: CloudKitMagicCRUD provides robust support for handling references between objects.
* **Working with Subscriptions and Notifications**: The package provides a simplified interface for working with CloudKit subscriptions and notifications.

## Getting Started

### Configuring Your Project

1. Import the CloudKitMagicCRUD package into your project.
2. Enable iCloud on your project.
3. Ensure that CloudKit service is marked.
4. Select or create a Container for the project.
5. Verify that your Container exists in your iCloud dashboard by visiting [https://icloud.developer.apple.com/dashboard/](https://icloud.developer.apple.com/dashboard/).
6. In AppDelegate's `didFinishLaunchingWithOptions` function or in SwiftUI `@main` struct, set your container:

```swift
CKMDefault.containerIdentifier = "iCloud.My.CloudContainer"
```

### Creating Your Data Models

1. Create your data model classes or structs.
2. Import CloudKitMagicCRUD.
3. Conform them to the `CKMCloudable` protocol.

```swift
import CloudKitMagicCRUD

struct MyModel: CKMCloudable {
    // Required properties from CKMRecord
    var recordName: String?
    var createdBy: String?
    var createdAt: Date?
    var modifiedBy: String?
    var modifiedAt: Date?
    var changeTag: String?
    
    // Your custom properties
    var title: String
    var description: String
    var isCompleted: Bool
    
    // Required by CKMCloudable
    static var ckRecordType: String = "MyModel"
}
```

## Basic CRUD Operations

### Using Async/Await (iOS 15+, watchOS 8+)

The package provides modern async/await methods for all CloudKit operations:

```swift
// Save a record
let savedRecord = try await myObject.ckSaveAsync()

// Load a record by ID
let loadedRecord = try await MyModel.ckLoadAsync(with: "record-id")

// Delete a record
let deletedRecordID = try await myObject.ckDeleteAsync()

// Delete a record and all its references in a cascading manner
let deletedRecordWithRefsID = try await myObject.ckDeleteCascadeAsync()

// Load all records
let result = try await MyModel.ckLoadAllAsync()
```

### Using Completion Handlers (All Platforms)

For backward compatibility, all operations are also available with completion handlers:

```swift
// Save a record with completion handler
myObject.ckSave { result in
    switch result {
    case .success(let savedRecord):
        print("Record saved: \(savedRecord)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// Delete a record with all its references in a cascading manner
myObject.ckDeleteCascade { result in
    switch result {
    case .success(let recordName):
        print("Record and all its references deleted: \(recordName)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// Load a record with completion handler
MyModel.ckLoad(with: "record-id") { result in
    switch result {
    case .success(let loadedRecord):
        print("Record loaded: \(loadedRecord)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

## Advanced Features

### Configuration Options

You can customize the behavior of CloudKitMagicCRUD using the configuration system:

```swift
// Use the default configuration
CKMDefault.configuration = CKMConfiguration.default

// Use a performance-optimized configuration
CKMDefault.configuration = CKMConfiguration.performanceOptimized

// Create a custom configuration
CKMDefault.configuration = CKMConfiguration(
    recordIDStrategy: .uuid,
    useCloudKitRecordIDAsIdentifier: true,
    cacheConfiguration: CKMConfiguration.CacheConfiguration(
        isCachingEnabled: true,
        expirationTimeInterval: 120.0,
        maxCacheSize: 500
    ),
    errorHandlingConfiguration: CKMConfiguration.ErrorHandlingConfiguration(
        logErrorsToConsole: true,
        includeDetailedFieldInfo: true
    )
)
```

### Record ID Management

You can configure how record IDs are generated and managed:

```swift
// Use auto-generated IDs
CKMDefault.configuration.recordIDStrategy = .autoGenerated

// Use UUIDs
CKMDefault.configuration.recordIDStrategy = .uuid

// Use a custom ID generator
CKMDefault.configuration.recordIDStrategy = .custom {
    return "custom-\(Date().timeIntervalSince1970)"
}

// Use a property from the model
CKMDefault.configuration.recordIDStrategy = .modelProperty(keyPath: "id")

// Use CloudKit record ID as the primary identifier
CKMDefault.configuration.useCloudKitRecordIDAsIdentifier = true
```

### Caching Configuration

You can customize how records are cached to optimize performance:

```swift
// Configure caching
CKMDefault.configuration.cacheConfiguration = CKMConfiguration.CacheConfiguration(
    isCachingEnabled: true,         // Enable or disable caching
    expirationTimeInterval: 300.0,  // Cache expiration time in seconds
    maxCacheSize: 1000              // Maximum number of records to cache
)
```

#### Caching Best Practices

1. For frequently accessed records, increase the cache expiration time:
   ```swift
   CKMDefault.configuration.cacheConfiguration.expirationTimeInterval = 600.0 // 10 minutes
   ```

2. For memory-constrained environments, limit the cache size:
   ```swift
   CKMDefault.configuration.cacheConfiguration.maxCacheSize = 100
   ```

3. For data that changes frequently, use a shorter cache expiration time or disable caching for specific operations by clearing the cache before loading:
   ```swift
   CKMDefault.removeFromCache(recordID)
   ```

### Explicit Record Operations

The package provides explicit methods for different record operations:

```swift
// Create a new record (fails if record with same ID exists)
let newRecord = try await myObject.ckInsertAsync()

// Update an existing record (fails if record doesn't exist)
let updatedRecord = try await myObject.ckUpdateAsync()

// Intelligently insert or update based on record existence
let savedRecord = try await myObject.ckUpsertAsync()
```

These methods provide better error handling and clearer semantics than the original approach.

### Custom Codable Implementation

You can customize how your models are encoded and decoded by conforming to `CKMCustomCodable`:

```swift
struct MyModel: CKMCloudable, CKMCustomCodable {
    var recordName: String?
    var createdBy: String?
    var createdAt: Date?
    var modifiedBy: String?
    var modifiedAt: Date?
    var changeTag: String?
    
    var name: String
    var customField: CustomType
    
    // Custom encoding logic
    func ckCustomEncode() throws -> [String: Any] {
        var dictionary = try CKMCodableHelpers.encode(self)
        dictionary["customField"] = customField.specialEncode()
        return dictionary
    }
    
    // Custom decoding logic
    static func ckCustomDecode(from dictionary: [String: Any]) throws -> Self {
        var model = try CKMCodableHelpers.decode(dictionary) as MyModel
        if let customData = dictionary["customField"] as? [String: Any] {
            model.customField = CustomType.specialDecode(from: customData)
        }
        return model
    }
}
```

This is useful when you have custom types that need special handling during CloudKit serialization.

### Handling References Between Objects

CloudKitMagicCRUD provides robust support for handling references between objects. Here's how to work with references:

```swift
// Define models with references
struct Department: CKMCloudable {
    var recordName: String?
    var createdBy: String?
    var createdAt: Date?
    var modifiedBy: String?
    var modifiedAt: Date?
    var changeTag: String?
    
    var name: String
    var employees: [Employee]? // Reference to other CKMCloudable objects
    
    static var ckRecordType: String = "Department"
}

struct Employee: CKMCloudable {
    var recordName: String?
    var createdBy: String?
    var createdAt: Date?
    var modifiedBy: String?
    var modifiedAt: Date?
    var changeTag: String?
    
    var name: String
    var department: Department? // Reference to another CKMCloudable object
    
    static var ckRecordType: String = "Employee"
}

// Save objects with references
func saveWithReferences() async throws {
    // Create and save a department
    var department = Department(name: "Engineering", employees: [])
    department = try await department.ckSaveAsync()
    
    // Create employees with reference to department
    var employee1 = Employee(name: "Alice", department: department)
    var employee2 = Employee(name: "Bob", department: department)
    
    // Save employees
    employee1 = try await employee1.ckSaveAsync()
    employee2 = try await employee2.ckSaveAsync()
    
    // Update department with references to employees
    department.employees = [employee1, employee2]
    department = try await department.ckSaveAsync()
}

// Load objects with references
func loadWithReferences() async throws {
    // Load a department with its ID
    let department = try await Department.ckLoadAsync(with: "department-id")
    
    // Access referenced employees
    if let employees = department.employees {
        for employee in employees {
            print("Employee: \(employee.name)")
        }
    }
}

#### Cascade Deletion of Referenced Objects

When you need to delete an object along with all its referenced objects, use the cascade delete functionality:

```swift
// Delete a department and all its employees
func deleteDepartmentWithEmployees() async throws {
    let department = try await Department.ckLoadAsync(with: "department-id")
    
    // This will delete the department and all referenced employees
    try await department.ckDeleteCascadeAsync()
}
```

The cascade delete operation:
1. Identifies all referenced objects (direct and indirect)
2. Deletes each referenced object first
3. Finally deletes the parent object
4. Cleans up the cache for all deleted objects

This is particularly useful for maintaining data integrity and avoiding orphaned records in your CloudKit database.

#### Handling Circular References

CloudKitMagicCRUD automatically detects and handles circular references. When saving objects with circular references, the package will:

1. Detect the circular reference
2. Save one object first
3. Update the other object with the reference
4. Handle all necessary record linking

#### Advanced Reference Cycle Handling

CloudKitMagicCRUD provides both synchronous and asynchronous methods for handling reference cycles when loading objects:

##### Synchronous Loading (Legacy)

The synchronous loading method now safely handles reference cycles by returning a simplified reference object instead of crashing:

```swift
// When a cycle is detected in synchronous loading, a simplified reference is returned
if let refDict = value as? [String: Any], 
   let isCycle = refDict["__isCycleReference"] as? Bool, 
   isCycle == true {
    // Handle the cycle (e.g., lazy loading or displaying a placeholder)
    print("Cycle detected in reference with recordName: \(refDict["recordName"] ?? "unknown")")
}
```

##### Asynchronous Loading (Recommended)

For modern Swift code, use the async alternatives which provide better performance and more graceful cycle handling:

```swift
// Example of using the async methods to handle cycles
func loadObjectWithCycles() async throws {
    let record = try await CKMDefault.database.record(for: recordID)
    
    // Convert to dictionary with cycle handling
    let dictionary = try await record.asDictionaryAsync()
    
    // Process the dictionary and handle any cycles
    for (key, value) in dictionary {
        if let refDict = value as? [String: Any], 
           let isCycle = refDict["__isCycleReference"] as? Bool, 
           isCycle == true {
            // Handle the cycle (e.g., lazy loading or displaying a placeholder)
            print("Cycle detected in reference: \(key)")
        }
    }
}
```

The async methods offer several advantages:
- They don't block threads with semaphores
- They properly propagate errors with try/catch
- They track loaded records to prevent infinite recursion
- They gracefully handle cycles by returning simplified references

This approach is particularly useful for complex data models with bidirectional relationships or deep object graphs.

### Working with Subscriptions and Notifications

CloudKitMagicCRUD provides a simplified interface for working with CloudKit subscriptions and notifications. The system automatically prevents duplicate subscriptions and offers both completion handler and async/await APIs.

#### Setting Up Notifications

To use silent notifications, you must set up an AppDelegate:

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) async -> UIBackgroundFetchResult {
        CKMNotificationManager.notificationHandler(userInfo: userInfo)
        return .newData
    }
}
```

In SwiftUI, you can use `@UIApplicationDelegateAdaptor`:

```swift
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

#### Creating Subscriptions

CloudKitMagicCRUD provides two ways to create and manage subscriptions:

##### Using CKMCloudable Extension Methods

The simplest way to register for notifications is to use the extension methods on your model:

```swift
// Register for notifications using completion handler
MyModel.register(observer: self)

// Register for notifications using async/await (iOS 15+)
try await MyModel.registerAsync(observer: self)
```

Your class must conform to the `CKMRecordObserver` protocol:

```swift
class MyViewController: UIViewController, CKMRecordObserver {
    func onReceive(notification: CKMNotification) {
        if let recordID = notification.recordID {
            // Handle the notification
            print("Received notification for record: \(recordID)")
        }
    }
}
```

##### Manual Subscription Creation

For more control, you can create subscriptions manually:

```swift
// Create a subscription to be notified when records change
func createSubscription() async throws {
    let subscription = CKQuerySubscription(
        recordType: "MyModel",
        predicate: NSPredicate(value: true),
        subscriptionID: "all-mymodels-changes",
        options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
    )
    
    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.shouldSendContentAvailable = true // For silent notifications
    subscription.notificationInfo = notificationInfo
    
    try await CKMDefault.database.save(subscription)
}
```

The package also provides methods to manage subscriptions with duplicate prevention:

```swift
// Using completion handler
CKMDefault.notificationManager.createNotification(
    to: observer,
    for: MyModel.self,
    completion: { result in
        switch result {
        case .success(let subscription):
            print("Subscription created or found: \(subscription.subscriptionID)")
        case .failure(let error):
            print("Error creating subscription: \(error.localizedDescription)")
        }
    }
)

// Using async/await (iOS 15+)
do {
    let subscription = try await CKMDefault.notificationManager.createNotificationAsync(
        to: observer,
        for: MyModel.self
    )
    print("Subscription created or found: \(subscription.subscriptionID)")
} catch {
    print("Error creating subscription: \(error.localizedDescription)")
}
```

#### Handling Notifications

To catch the notifications sent by your subscriptions, use the package's publisher:

```swift
struct ContentView: View {
    var body: some View {
        Text("CloudKit Notifications Demo")
            .onReceive(CKMNotificationManager.receivedNotificationPublisher) { notification in
                if let recordID = notification.recordID {
                    // Handle the notification
                    print("Received notification for record: \(recordID)")
                }
            }
    }
}
```

With silent notifications, only category, recordID, subscriptionID, zoneID, and userID are available. It is strongly suggested to use only the category and the recordID.

#### Required Background Modes

Don't forget to add the background modes capability to your project, with background fetch and remote notifications enabled:

```xml
<key>UIBackgroundModes</key>
    <array>
        <string>fetch</string>
        <string>remote-notification</string>
    </array>
```

#### Subscription Types

CloudKit supports several types of subscriptions:

1. **Query Subscriptions**: Notify when records matching a query change
2. **Record Zone Subscriptions**: Notify when any record in a zone changes
3. **Database Subscriptions**: Notify when any record in the database changes

Example of a zone subscription:

```swift
func subscribeToZone(zoneID: CKRecordZone.ID) async throws {
    let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "zone-\(zoneID.zoneName)")
    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.shouldSendContentAvailable = true
    subscription.notificationInfo = notificationInfo
    
    try await CKMDefault.database.save(subscription)
}
```

### Query Optimization

When fetching multiple records:

1. Use specific predicates instead of fetching all records:
   ```swift
   let predicate = NSPredicate(format: "category == %@", "important")
   let results = try await MyModel.ckLoadAllAsync(predicate: predicate)
   ```

2. Use sort descriptors to get the most important records first:
   ```swift
   let sortDescriptor = CKSortDescriptor(key: "createdAt", ascending: false)
   let results = try await MyModel.ckLoadAllAsync(sortedBy: [sortDescriptor], limit: 20)
   ```

3. Use pagination for large datasets:
   ```swift
   // First page
   let (records, cursor) = try await MyModel.ckLoadAllAsync(limit: 50)
   
   // Next page (if cursor exists)
   if let cursor = cursor {
       let (nextRecords, nextCursor) = try await MyModel.ckLoadNextAsync(cursor: cursor, limit: 50)
   }
   ```

### Batch Operations

For better performance when working with multiple records:

1. Use the batch save methods when available
2. Consider implementing your own batching for large operations:
   ```swift
   // Example of manual batching
   func saveInBatches(records: [MyModel], batchSize: Int = 100) async throws {
       for batch in records.chunked(into: batchSize) {
           try await withThrowingTaskGroup(of: Void.self) { group in
               for record in batch {
                   group.addTask {
                       _ = try await record.ckSaveAsync()
                   }
               }
               try await group.waitForAll()
           }
       }
   }
   
   // Helper extension
   extension Array {
       func chunked(into size: Int) -> [[Element]] {
           return stride(from: 0, to: count, by: size).map {
               Array(self[$0..<Swift.min($0 + size, count)])
           }
       }
   }
   ```

These methods provide better error handling and clearer semantics than the original approach.

### Error Handling

CloudKitMagicCRUD provides enhanced error handling with detailed information about which field caused an issue.

### Error Types

The package defines its own error types in the `CRUDError` enum, which provides specific information about what went wrong during CloudKit operations.

### Comprehensive Error Handling Example

```swift
do {
    let savedRecord = try await myObject.ckUpsertAsync()
} catch let error as CKError {
    switch error.code {
    case .networkFailure, .networkUnavailable:
        // Handle network connectivity issues
        print("Network unavailable. Please check your connection.")
    case .serverResponseLost, .serviceUnavailable:
        // Handle CloudKit service issues
        print("CloudKit service unavailable. Please try again later.")
    case .quotaExceeded:
        // Handle quota issues
        print("CloudKit quota exceeded. Please try again tomorrow.")
    case .zoneNotFound, .unknownItem:
        // Handle missing records/zones
        print("The requested item could not be found.")
    case .notAuthenticated:
        // Handle authentication issues
        print("Please sign in to iCloud to use this feature.")
    default:
        // Handle other CloudKit errors
        print("CloudKit error: \(error.localizedDescription)")
    }
} catch let error as CRUDError {
    // Handle CloudKitMagicCRUD specific errors
    print("CRUD error: \(error.localizedDescription)")
    
    // You can also get the failure reason
    if let localizedError = error as? LocalizedError, 
       let reason = localizedError.failureReason {
        print("Reason: \(reason)")
    }
} catch {
    // Handle other errors
    print("Error: \(error.localizedDescription)")
}
```

## Troubleshooting Common Issues

### CloudKit Container Configuration

If you're experiencing issues with CloudKit connectivity:

1. Verify your entitlements file has the correct container identifier
2. Ensure the container exists in the CloudKit Dashboard
3. Check that you've properly set the container identifier in your code:

```swift
CKMDefault.containerIdentifier = "iCloud.com.yourcompany.yourapp"
```

### Permission Issues

CloudKit requires proper permissions:

1. Ensure your app has requested permission to use CloudKit
2. For user data, make sure you're using the private database with proper authentication
3. For public data, ensure your schema is properly configured in the CloudKit Dashboard

## Migration Guide from Previous Versions

If you're upgrading from an older version of CloudKitMagicCRUD, follow these steps:

### Migrating from Completion Handlers to Async/Await

1. Replace completion handler-based calls with async/await equivalents:

   **Before:**
   ```swift
   myObject.ckSave { result in
       switch result {
       case .success(let savedRecord):
           // Handle success
       case .failure(let error):
           // Handle error
       }
   }
   ```

   **After:**
   ```swift
   do {
       let savedRecord = try await myObject.ckSaveAsync()
       // Handle success
   } catch {
       // Handle error
   }
   ```

2. Update your error handling:

   **Before:**
   ```swift
   MyModel.ckLoad(with: recordID) { result in
       if case .failure(let error) = result {
           print("Error: \(error)")
       }
   }
   ```

   **After:**
   ```swift
   do {
       let record = try await MyModel.ckLoadAsync(with: recordID)
   } catch {
       print("Error: \(error)")
   }
   ```

3. For batch operations, consider using Task groups:

   **Before:**
   ```swift
   let group = DispatchGroup()
   for item in items {
       group.enter()
       item.ckSave { _ in group.leave() }
   }
   group.notify(queue: .main) {
       // All saves completed
   }
   ```

   **After:**
   ```swift
   try await withThrowingTaskGroup(of: Void.self) { group in
       for item in items {
           group.addTask {
               _ = try await item.ckSaveAsync()
           }
       }
       try await group.waitForAll()
       // All saves completed
   }
   ```

### Adopting New Configuration Options

If you're using the default configuration, update to use the new configuration system:

```swift
// Before (implicit defaults)
// No configuration needed

// After (explicit configuration)
CKMDefault.configuration = CKMConfiguration.default

// Or with custom settings
CKMDefault.configuration = CKMConfiguration(
    recordIDStrategy: .uuid,
    useCloudKitRecordIDAsIdentifier: true,
    cacheConfiguration: CKMConfiguration.CacheConfiguration(
        isCachingEnabled: true,
        expirationTimeInterval: 120.0,
        maxCacheSize: 500
    )
)
```

## API Reference

### Core Classes and Protocols

#### CKMDefault

The central configuration class for CloudKitMagicCRUD:

```swift
class CKMDefault { 
    // The default database identifier
    // By default gets the CKContainer.default().publicCloudDatabase value
    static var containerIdentifier: String { get set }
    
    // The Notification Manager unique shared instance
    static var notificationManager: CKMNotificationManager { get }
    
    // Configuration for CloudKitMagicCRUD
    static var configuration: CKMConfiguration { get set }
    
    // The default container (same as CKContainer.default())
    static var container: CKContainer { get }
    
    // The database to use for operations
    static var database: CKDatabase { get set }
    
    // The default semaphore for awaiting subqueries
    static var semaphore: DispatchObject { get }
    
    // Record type naming helpers
    static func setRecordTypeFor<T: CKMRecord>(_ object: T, recordName: String)
    static func getRecordTypeFor<T: CKMRecord>(_ object: T) -> String
}
```

#### CKMCloudable Protocol

The main protocol for CloudKit-compatible objects:

```swift
protocol CKMCloudable: CKMRecord {
    // Core functionality
    func ckSave(then completion: @escaping (Result<Any, Error>) -> Void)
    func ckDelete(then completion: @escaping (Result<CKRecord.ID, Error>) -> Void)
    static func ckLoad(with recordName: String, then completion: @escaping (Result<Self, Error>) -> Void)
    static func ckLoadAll(predicate: NSPredicate, sortedBy: [CKSortDescriptor], limit: Int, then completion: @escaping (Result<([Any], CKQueryOperation.Cursor?), Error>) -> Void)
    
    // Async/await methods (iOS 15+, watchOS 8+)
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    func ckSaveAsync() async throws -> Self
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    func ckDeleteAsync() async throws -> CKRecord.ID
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    static func ckLoadAsync(with recordName: String) async throws -> Self
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    static func ckLoadAllAsync(predicate: NSPredicate, sortedBy: [CKSortDescriptor], limit: Int) async throws -> ([Self], CKQueryOperation.Cursor?)
    
    // Explicit record operations (iOS 15+, watchOS 8+)
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    func ckInsertAsync() async throws -> Self
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    func ckUpdateAsync() async throws -> Self
    
    @available(iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, *)
    func ckUpsertAsync() async throws -> Self
}
```

#### CKMRecord Protocol

The base protocol for CloudKit records:

```swift
protocol CKMRecord {
    // Required properties
    var recordName: String? { get set }
    
    // Optional properties
    var createdBy: String? { get }
    var createdAt: Date? { get }
    var modifiedBy: String? { get }
    var modifiedAt: Date? { get }
    var changeTag: String? { get }
    
    // Converts a CloudKit.CKRecord into an object
    static func load(from record: CKRecord) throws -> Self
}
```

### Utility Extensions

CloudKitMagicCRUD provides several extensions to make working with Codable types easier:

```swift
extension Encodable {
    // Convert to string representation
    var asString: String? { get }
    
    // Convert to JSON data
    var jsonData: Data? { get }
    
    // Convert to dictionary
    var asDictionary: [String: Any]? { get }
    
    // Convert to array
    var asArray: [Any]? { get }
    
    // Save to default location
    func save() throws
    
    // Save to specified file
    func save(in file: String?) throws
    
    // Save to URL
    func save(in url: URL) throws
}

extension Decodable {
    // Mutating load methods
    mutating func load(from data: Data) throws
    mutating func load(from url: URL) throws
    mutating func load() throws
    mutating func load(from file: String?) throws
    mutating func load(fromStringData stringData: String) throws
    mutating func load(from dictionary: [String: Any]) throws
    mutating func load(from array: [Any]) throws
    
    // Static load methods
    static func load(from data: Data) throws -> Self
    static func load(from url: URL) throws -> Self
    static func load() throws -> Self
    static func load(from file: String?) throws -> Self
    static func load(fromString stringData: String) throws -> Self
    static func load(from dictionary: [String: Any]) throws -> Self
    static func load(from array: [Any]) throws -> Self
    
    // URL helpers
    static func url() -> URL
    static func url(from file: String?) -> URL
}
```

These extensions are particularly useful when you need to convert between different data formats or save/load objects to disk.

#### CertifiedCodableData

A utility struct for working with dictionaries that aren't natively Codable:

```swift
struct CertifiedCodableData: Codable {
    // Access the underlying dictionary
    var dictionary: [String: Any] { get }
    
    // Create from a dictionary
    init(_ originalData: [String: Any])
}
```

This is useful when you have custom types that need special handling during CloudKit serialization.
