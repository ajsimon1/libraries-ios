import CoreData
import CloudKit
import SwiftUI

final class PersistenceController {
    static let shared = PersistenceController()

    static let cloudKitContainerID = "iCloud.com.ajsimon1.SharedShelf"

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    // Store references for scoping fetches
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SharedShelf")

        let storesURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!

        // Private store (your own libraries)
        let privateURL = storesURL.appendingPathComponent("private.sqlite")
        let privateDesc = NSPersistentStoreDescription(url: privateURL)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if !inMemory {
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            privateOptions.databaseScope = .private
            privateDesc.cloudKitContainerOptions = privateOptions
        }

        // Shared store (libraries shared to you)
        let sharedURL = storesURL.appendingPathComponent("shared.sqlite")
        let sharedDesc = NSPersistentStoreDescription(url: sharedURL)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if !inMemory {
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            sharedOptions.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = sharedOptions
        }

        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
            sharedDesc.url = URL(fileURLWithPath: "/dev/null/shared")
        }

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        container.loadPersistentStores { desc, error in
            if let error {
                fatalError("Failed to load persistent store: \(error)")
            }
        }

        // Capture store references
        for store in container.persistentStoreCoordinator.persistentStores {
            if store.url?.lastPathComponent == "private.sqlite" {
                privateStore = store
            } else {
                sharedStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Store Helpers

    func isShared(_ object: NSManagedObject) -> Bool {
        guard let sharedStore,
              let objectStore = object.objectID.persistentStore else { return false }
        return objectStore == sharedStore
    }

    func isOwner(_ object: NSManagedObject) -> Bool {
        !isShared(object)
    }

    // MARK: - Sharing

    func shareLibrary(
        _ library: CDLibrary,
        completion: @escaping (CKShare?, CKContainer?, Error?) -> Void
    ) {
        container.share([library], to: nil) { objectIDs, share, ckContainer, error in
            if let share {
                share[CKShare.SystemFieldKey.title] = library.name
            }
            DispatchQueue.main.async {
                completion(share, ckContainer, error)
            }
        }
    }

    func existingShare(for library: CDLibrary) -> CKShare? {
        try? container.fetchShares(matching: [library.objectID])[library.objectID]
    }

    func acceptShare(metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(
            from: [metadata],
            into: sharedStore
        ) { _, error in
            if let error {
                print("Failed to accept share: \(error)")
            }
        }
    }
}

// Custom environment key for PersistenceController
private struct PersistenceControllerKey: EnvironmentKey {
    static let defaultValue = PersistenceController.shared
}

extension EnvironmentValues {
    var persistenceController: PersistenceController {
        get { self[PersistenceControllerKey.self] }
        set { self[PersistenceControllerKey.self] = newValue }
    }
}
