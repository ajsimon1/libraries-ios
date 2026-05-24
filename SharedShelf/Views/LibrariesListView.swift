import SwiftUI
import CoreData
import CloudKit

struct LibrariesListView: View {
    let shared: Bool
    @Environment(\.persistenceController) private var persistence
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddLibrary = false
    @State private var activeShare: CKShareTransfer?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLibrary.createdAt, ascending: true)]
    ) private var allLibraries: FetchedResults<CDLibrary>

    private var libraries: [CDLibrary] {
        allLibraries.filter { library in
            shared ? persistence.isShared(library) : !persistence.isShared(library)
        }
    }

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle(shared ? "Shared With Me" : "My Libraries")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        addButton
                        #if DEBUG
                        if shared { debugSeedMenu }
                        #endif
                    }
                }
                .sheet(isPresented: $showingAddLibrary) {
                    AddLibraryView()
                }
                .sheet(item: $activeShare) { (transfer: CKShareTransfer) in
                    CloudSharingView(
                        share: transfer.share,
                        container: transfer.container,
                        library: transfer.library
                    )
                }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if libraries.isEmpty {
            ContentUnavailableView(
                shared ? "No Shared Libraries" : "No Libraries Yet",
                systemImage: shared ? "person.2" : "books.vertical",
                description: Text(shared
                    ? "Libraries shared with you will appear here."
                    : "Tap + to create your first library.")
            )
        } else {
            libraryList
        }
    }

    private var libraryList: some View {
        List {
            ForEach(libraries) { library in
                NavigationLink(destination: MyBooksView(library: library, isOwner: !shared)) {
                    LibraryRow(library: library, showOwner: shared)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        shareLibrary(library)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.indigo)
                }
            }
            .onDelete { offsets in
                let toDelete = offsets.map { libraries[$0] }
                for library in toDelete { viewContext.delete(library) }
                try? viewContext.save()
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if !shared {
            Button(action: { showingAddLibrary = true }) {
                Image(systemName: "plus")
            }
        }
    }

    #if DEBUG
    private var debugSeedMenu: some View {
        Menu {
            Button {
                persistence.pushFullSchema()
            } label: {
                Label("Push CloudKit schema", systemImage: "icloud.and.arrow.up")
            }
            Button {
                persistence.seedFakeSharedLibrary()
            } label: {
                Label("Seed test data", systemImage: "plus.square.on.square")
            }
            Section("Mimic owner") {
                Button {
                    persistence.approvePendingDemoRequests()
                } label: {
                    Label("Approve pending requests", systemImage: "checkmark.circle")
                }
                Button {
                    persistence.declinePendingDemoRequests()
                } label: {
                    Label("Decline pending requests", systemImage: "xmark.circle")
                }
            }
            Button(role: .destructive) {
                persistence.clearTestData()
            } label: {
                Label("Clear test data", systemImage: "trash")
            }
        } label: {
            Image(systemName: "flask")
        }
    }
    #endif

    private func shareLibrary(_ library: CDLibrary) {
        if let existingShare = persistence.existingShare(for: library) {
            let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            activeShare = CKShareTransfer(share: existingShare, container: ckContainer, library: library)
            return
        }

        persistence.shareLibrary(library) { share, ckContainer, error in
            if let share, let ckContainer {
                activeShare = CKShareTransfer(share: share, container: ckContainer, library: library)
            }
        }
    }
}

struct CKShareTransfer: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
    let library: CDLibrary
}

struct LibraryRow: View {
    @ObservedObject var library: CDLibrary
    var showOwner: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(library.emoji ?? "📚")
                .font(.system(size: 36))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(library.name ?? "Untitled")
                    .font(.headline)
                if showOwner, let owner = library.ownerName, !owner.isEmpty {
                    Text(owner)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                let count = library.books?.count ?? 0
                Text("\(count) book\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ownerName = ""
    @State private var emoji = "📚"

    private let emojiOptions = ["📚", "📖", "📕", "📗", "📘", "📙", "🏠", "🏛️", "🎓", "👨‍👩‍👧‍👦", "👴", "🧒"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Library Info") {
                    TextField("Library Name", text: $name)
                    TextField("Owner Name (optional)", text: $ownerName)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiOptions, id: \.self) { option in
                            Text(option)
                                .font(.system(size: 32))
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(emoji == option ? .indigo.opacity(0.2) : .clear)
                                )
                                .onTapGesture { emoji = option }
                        }
                    }
                }
            }
            .navigationTitle("New Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let library = CDLibrary(context: viewContext)
                        library.name = name.trimmingCharacters(in: .whitespaces)
                        library.ownerName = ownerName.trimmingCharacters(in: .whitespaces)
                        library.emoji = emoji
                        library.createdAt = Date()
                        try? viewContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
