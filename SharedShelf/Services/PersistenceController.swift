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

    // MARK: - Borrowed-book lookup + return

    /// Finds the approved CDBookRequest backing a borrowed copy, if any. Matches by ISBN +
    /// the library the requester picked at request time (stored on the request as
    /// requesterLibraryName, mirrored as the copy's library.name).
    func borrowRequest(for copy: CDBook) -> CDBookRequest? {
        guard let isbn = copy.isbn, !isbn.isEmpty,
              let libraryName = copy.library?.name else { return nil }
        let fetch = NSFetchRequest<CDBookRequest>(entityName: "CDBookRequest")
        fetch.predicate = NSPredicate(
            format: "status == %@ AND requesterLibraryName == %@ AND book.isbn == %@",
            "approved", libraryName, isbn
        )
        fetch.fetchLimit = 1
        return try? viewContext.fetch(fetch).first
    }

    /// Marks the source book available again, flips the request status to "returned", and
    /// deletes the borrower's local copy. Safe to call even if no matching request exists —
    /// the copy is removed regardless so the user can always clean up their library.
    func returnBorrowedBook(_ copy: CDBook) {
        let ctx = viewContext
        if let request = borrowRequest(for: copy) {
            request.status = "returned"
            request.book?.isAvailable = true
        }
        ctx.delete(copy)
        try? ctx.save()
    }

#if DEBUG
    // MARK: - Schema (DEBUG only)

    /// Forces CloudKit to push the full schema for every entity in the data model.
    /// Use once after schema changes to ensure all record types exist in the Development
    /// environment before deploying to Production. Apple's API generates temp records of every
    /// type, uploads the schema, then cleans up.
    func pushFullSchema() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try container.initializeCloudKitSchema(options: [])
                print("CloudKit schema pushed successfully — refresh Dashboard.")
            } catch {
                print("CloudKit schema push FAILED: \(error)")
            }
        }
    }

    // MARK: - Test Data (DEBUG only)

    /// Inserts a fake "shared with me" library + 3 books into the shared store so the
    /// request-to-borrow flow can be exercised on a single simulator without real CloudKit sharing.
    /// Objects are local-only — without an iCloud account the shared store doesn't sync anywhere.
    func seedFakeSharedLibrary() {
        guard let sharedStore else { return }
        let ctx = viewContext

        let library = CDLibrary(context: ctx)
        library.name = "Dad's Books (Demo)"
        library.ownerName = "Dad"
        library.emoji = "👴"
        library.createdAt = Date()
        ctx.assign(library, to: sharedStore)

        let books: [(title: String, author: String, isbn: String, year: String, pages: Int32)] = [
            ("The Old Man and the Sea", "Ernest Hemingway", "9780684830490", "1952", 127),
            ("The Great Gatsby", "F. Scott Fitzgerald", "9780743273565", "1925", 180),
            ("Catch-22", "Joseph Heller", "9781451626650", "1961", 453),
        ]
        for entry in books {
            let book = CDBook(context: ctx)
            book.title = entry.title
            book.author = entry.author
            book.isbn = entry.isbn
            book.publishYear = entry.year
            book.pageCount = entry.pages
            book.isAvailable = true
            book.ownerName = "Dad"
            book.createdAt = Date()
            book.library = library
            ctx.assign(book, to: sharedStore)
        }

        try? ctx.save()
    }

    /// Flips every pending request on a seeded (shared-store) book to approved, mimicking the
    /// other user (the "owner") approving from their device. Marks the book unavailable and
    /// copies the book into the requester's "Borrowed" library so it shows up in My Libraries.
    /// In real CloudKit world the copy would be triggered on the requester's device by a
    /// status-change observer — until that exists, the debug action simulates both sides.
    func approvePendingDemoRequests() {
        guard let sharedStore else { return }
        let ctx = viewContext

        let request = NSFetchRequest<CDBookRequest>(entityName: "CDBookRequest")
        request.predicate = NSPredicate(format: "status == %@", "pending")
        guard let pending = try? ctx.fetch(request) else { return }

        for r in pending where r.book?.objectID.persistentStore == sharedStore {
            r.status = "approved"
            if let source = r.book {
                source.isAvailable = false
                let destination = destinationLibrary(for: r)
                copyBookForBorrowing(source, into: destination)
            }
        }
        try? ctx.save()
    }

    /// Resolves the library to copy the borrowed book into. Prefers the library the requester
    /// selected when filing the request; falls back to the auto "Borrowed" library if the
    /// referenced library is missing (e.g., deleted) or the request predates the field.
    private func destinationLibrary(for request: CDBookRequest) -> CDLibrary {
        if let name = request.requesterLibraryName,
           !name.isEmpty,
           let library = findPrivateLibrary(named: name) {
            return library
        }
        return findOrCreateBorrowedLibrary()
    }

    private func findPrivateLibrary(named name: String) -> CDLibrary? {
        guard let privateStore else { return nil }
        let fetch = NSFetchRequest<CDLibrary>(entityName: "CDLibrary")
        fetch.predicate = NSPredicate(format: "name == %@", name)
        fetch.affectedStores = [privateStore]
        fetch.fetchLimit = 1
        return try? viewContext.fetch(fetch).first
    }

    /// Returns the user's "Borrowed" library in the private store, creating it if needed.
    private func findOrCreateBorrowedLibrary() -> CDLibrary {
        let ctx = viewContext
        let fetch = NSFetchRequest<CDLibrary>(entityName: "CDLibrary")
        fetch.predicate = NSPredicate(format: "name == %@", "Borrowed")
        if let privateStore { fetch.affectedStores = [privateStore] }
        if let existing = try? ctx.fetch(fetch).first { return existing }

        let library = CDLibrary(context: ctx)
        library.name = "Borrowed"
        library.ownerName = ""
        library.emoji = "📥"
        library.createdAt = Date()
        if let privateStore { ctx.assign(library, to: privateStore) }
        return library
    }

    /// Copies the on-loan book's fields into a new CDBook placed in the borrowed library, with
    /// ownerName set to the original owner so the row can show "From: Dad". The source book in
    /// the shared store is left untouched (its owner still has it; it's just marked unavailable).
    private func copyBookForBorrowing(_ source: CDBook, into borrowed: CDLibrary) {
        let ctx = viewContext
        let copy = CDBook(context: ctx)
        copy.title = source.title
        copy.author = source.author
        copy.isbn = source.isbn
        copy.genre = source.genre
        copy.notes = source.notes
        copy.coverImageData = source.coverImageData
        copy.pageCount = source.pageCount
        copy.publishYear = source.publishYear
        copy.isAvailable = true
        copy.ownerName = source.library?.ownerName ?? source.ownerName
        copy.createdAt = Date()
        copy.library = borrowed
        if let privateStore { ctx.assign(copy, to: privateStore) }
    }

    /// Same as approvePendingDemoRequests but sets status to declined. Book stays available.
    func declinePendingDemoRequests() {
        guard let sharedStore else { return }
        let ctx = viewContext

        let request = NSFetchRequest<CDBookRequest>(entityName: "CDBookRequest")
        request.predicate = NSPredicate(format: "status == %@", "pending")
        guard let pending = try? ctx.fetch(request) else { return }

        for r in pending where r.book?.objectID.persistentStore == sharedStore {
            r.status = "declined"
        }
        try? ctx.save()
    }

    /// Deletes every object that lives in the shared store. Safe in the simulator where the
    /// shared store only contains seed data (no real iCloud share has been accepted).
    func clearTestData() {
        guard let sharedStore else { return }
        let ctx = viewContext

        for entityName in ["CDBookRequest", "CDBook", "CDLibrary"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [sharedStore]
            if let objects = try? ctx.fetch(request) {
                for object in objects { ctx.delete(object) }
            }
        }
        try? ctx.save()
    }
#endif
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
