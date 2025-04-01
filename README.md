# CloudKitMagic

## iOS 17 Modernization

This package has been updated to support iOS 17 and newer Swift versions. Key changes include:

- Fixed initialization issues with async/await CloudKit operations
- Improved error handling for older OS versions
- Updated notification handling for modern iOS versions
- Enhanced type safety in record loading and caching
- Removed external dependencies for better self-containment

## How to use it

### Configuring your project
1. Import this package
2. Enable iCloud on your project
1. Be sure that CloudKit service is marked
2. Select or Create a Container for the project
3. Be sure that you Container exists in your iCloud visiting  [https://icloud.developer.apple.com/dashboard/](https://icloud.developer.apple.com/dashboard/)
3. In AppDelegate, didFinishLaunchingWithOptions function or in SwiftUI @main add a line setting your container if needed as
```swift
  CKMDefault.containerIdentifier = "iCloud.My.CloudContainer"
```


### Creating your data

1. Create your data Model classes or structs
2. import CloudKitMagicCRUD
3. Conform them with CKMRecord


CKMRecord has a mandatory field and sobe optional fields

* Mandatory
  * recordName:String? -> When it's a saved record, contains the record ID

* Optionals
  * createdBy:String -> Contains creator RecordName
  * createdAt:Date -> Conntains creation Date
  * modifiedBy:String -> Contains last modifier RecordName
  * modifiedAt:Date -> Conntainslast modificatio Date
  * changeTag:String -> a tag that changes at each modification




## List main of Functions and capabilities
These are the main functionalities of this package
```swift

class CKMDefault { 
	/**
	The default database
	By dafault get the CKContainer.default().publicCloudDatabase value.
	Can be resseted to another value
	*/
	static var containerIdentifier:String { get set }
	
	/**
	The Notification Manager unique shared instance
	*/
	static var notificationManager:CKMNotificationManager  { get }
}
```

```swift
protocol CKMRecord {
	/// recordName is the unique iCloud object identifyer
	var recordName:String? { get set }
	
	/// optional iCloud record system data
	var createdBy:String? { get }
	var createdAt:Date? { get }
	var modifiedBy:String? { get }
	var modifiedAt:Date? { get }
	var changeTag:String? { get }

	/// Basic Record Managment
	
	/**
		Get or set the recordType name
		the default value is the type (class or struct) name
	*/
	static var ckRecordType: String { get set }
	
	/**
	Saves the object in iCloud, returning in a completion a Result Type
		Cases:
			.success(let record:CKMRecord) -> The saved record, with correct Object Type, in a Any shell.  Just cast this to it's original type.
			.failure(let error) an error
	*/
	func ckSave(then completion:@escaping (Result<Any, Error>)->Void)
	
	/**
	Read all records from a type
	- Parameters:
	- sortedBy a array of  SortDescriptors (or string array)
	- predicate a NSPredicate with some query  restrictions
	- returns: a (Result<Any, Error>) where Any contais a type objects array [T] in a completion handler
	*/
	static func ckLoadAll(sortedBy sortKeys:[CKSortDescriptor],
						  predicate:NSPredicate,
						  then completion:@escaping (Result<Any, Error>)->Void)
	
	
	/**
	Read all records from a type
	- Parameters:
	- recordName an iCloud recordName id for fetch
	- returns: a (Result<Any, Error>) where Any contais a CKMRecord type object  in a completion handler
	*/
	static func ckLoad(with recordName: String , then completion:@escaping (Result<Any, Error>)->Void)
	
	/**
	Deletes an object in iCloud
	The object must have a valid recordName
	- returns: a (Result<String, Error>)
	*/
	func ckDelete(then completion:@escaping (Result<String, Error>)->Void)

}
```

```swift
/// Protocol for CK Notification Observers be warned when some register changed
protocol CKMRecordObserver {
	func onChange(ckRecordtypeName:String)
}
```

```swift
/**
- Description
A String that have "⇩" as last character if it's SortDescriptor is descending
set the descriptos as descending using (ckSort.descending)
*/
typealias CKSortDescriptor = NSString
```

```swift
class CKMNotificationManager {
	func createNotification<T:CKMCloudable>(to recordObserver:CKMRecordObserver,
						for recordType:T.Type,
						options:CKQuerySubscription.Options?,
						predicate: NSPredicate?,
						alertBody:String?)
	
}
```

## Another capabilities

### List support of Functions and capabilities
Here are other functionalities of this package that you may need
```swift
class CKMDefault {
	/**
	The default container
	Same as CKContainer.default()
	*/
	static var container:CKContainer { get }
	
	static var database:CKDatabase { get set }
	
	/// The default semaphore for awaiting subqueries
	static var semaphore:DispatchObject { get }
		
	/** Time in seconds for cache expiration
		setted to 30s
	*/
	
	/// Naming Types to RecordType
	static func setRecordTypeFor<T:CKMRecord>(_ object:T, recordName:String)
	static func getRecordTypeFor<T:CKMRecord>(_ object:T)->String
	
}

```

```swift
protocol CKMRecord {
	/// Converts a CloudKit.CKRecord in an object
	static func load(from record:CKRecord)throws->Self
}
```

### Silent Notifications

New silent notifications were introduced to CloudKitMagic. To use them, you must setup a AppDelegate first.

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
It can be called using a @UIApplicationDelegateAdaptor in SwiftUI.

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

To catch the notifications sent by your subscriptions, you must call a .onReceive with the package's publisher on it.

```swift
.onReceive(CKMNotificationManager.receivedNotificationPublisher, perform: { notification in

	// deal with your notification here

})
```

With silent notifications, only category, recordID, subscriptionID, zoneID and userID are available. It is strongly suggested to used only the category and the recordID.

Also, don't forget to have the background modes capability added into the project, with background fetch and remote notifications enabled. 

```xml
<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>remote-notification</string>
	</array>
```


As this packages uses my also created CodableExtensions package, the follow functions and variables are also avaliable.

### From CodableExtensions

```swift
extension Encodable {
	
	var asString:String? { get }
	
	var jsonData:Data? { get }
	
	var asDictionary:[String: Any]? { get }
	
	var asArray:[Any]? { get }
	
	func save() throws
	
	func save(in file:String?) throws
	
	func save(in url:URL) throws
}

extension Decodable {
	
	/// Mutating Loads
	mutating func load(from data:Data) throws

	mutating func load(from url:URL) throws
	
	mutating func load() throws
	
	mutating func load(from file:String?) throws
	
	mutating func load(fromStringData stringData:String) throws
	
	mutating func load(from dictionary:[String:Any]) throws
	
	mutating func load(from array:[Any]) throws
	
	/// Static Loads
	static func load(from data:Data)throws ->Self
	
	static func load(from url:URL) throws  ->Self
	
	static func load()throws ->Self
	
	static func load(from file:String?)throws ->Self
	
	static func load(fromString stringData:String)throws ->Self
	
	static func load(from dictionary:[String:Any])throws ->Self
	
	static func load(from array:[Any])throws ->Self
	
	static func url()->URL
	
	static func url(from file:String?)->URL
	
}

/// Type Extensions
extension Data {
	
	var toText:String { get }
	
	var toDictionary:[AnyHashable:Any] { get }
	
	var toArray:[Codable]? { get }
	
	func convert<T>(to:T.Type) throws ->T where T:Codable
	
}

extension URL {
	var contentAsData:Data? { get }
}


extension Array {
	var asData:Data? { get }
}

extension Dictionary where Key == String { 
	var asData:Data? { get }
	
}

struct CertifiedCodableData:Codable {
	
	var dictionary:[String:Any] { get }
	
	init(_ originalData:[String:Any])
	
}
