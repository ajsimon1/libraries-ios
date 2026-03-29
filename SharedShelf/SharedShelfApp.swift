import SwiftUI

@main
struct SharedShelfApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(\.persistenceController, persistence)
        }
    }
}
