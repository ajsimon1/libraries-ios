import SwiftUI
import CoreData

struct BookDetailView: View {
    @ObservedObject var book: CDBook
    let isOwner: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.persistenceController) private var persistence
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingRequestSheet = false

    private var borrowedCopyRequest: CDBookRequest? {
        guard isOwner else { return nil }
        return persistence.borrowRequest(for: book)
    }
    private var isBorrowedCopy: Bool { borrowedCopyRequest != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover image
                if let imageData = book.coverImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.indigo.opacity(0.1))
                        .frame(height: 200)
                        .overlay {
                            VStack {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 50))
                                Text("No Cover")
                                    .font(.caption)
                            }
                            .foregroundStyle(.indigo.opacity(0.5))
                        }
                }

                // Book info
                VStack(alignment: .leading, spacing: 12) {
                    Text(book.title ?? "Untitled")
                        .font(.title)
                        .fontWeight(.bold)

                    if let author = book.author, !author.isEmpty {
                        Label(author, systemImage: "person")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        if let genre = book.genre, !genre.isEmpty {
                            Label(genre, systemImage: "tag")
                        }
                        if book.pageCount > 0 {
                            Label("\(book.pageCount) pages", systemImage: "doc.plaintext")
                        }
                        if let year = book.publishYear, !year.isEmpty {
                            Label(year, systemImage: "calendar")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let isbn = book.isbn, !isbn.isEmpty {
                        Label(isbn, systemImage: "barcode")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    if isOwner {
                        if isBorrowedCopy {
                            // Borrowed copy — show return action instead of owner controls
                            HStack {
                                Label("Borrowed", systemImage: "book.closed.fill")
                                    .foregroundStyle(.indigo)
                                Spacer()
                                Button("Return Book") {
                                    persistence.returnBorrowedBook(book)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        } else {
                            // Availability toggle for owner
                            Toggle(isOn: Binding(
                                get: { book.isAvailable },
                                set: { book.isAvailable = $0; try? viewContext.save() }
                            )) {
                                Label(
                                    book.isAvailable ? "Available" : "Lent Out",
                                    systemImage: book.isAvailable ? "checkmark.circle" : "clock"
                                )
                            }
                            .tint(.indigo)
                        }
                    } else {
                        // Borrow request for non-owner
                        let hasPendingRequest = (book.requests as? Set<CDBookRequest>)?
                            .contains { $0.status == "pending" } ?? false

                        HStack {
                            Label(
                                book.isAvailable ? "Available" : "Lent Out",
                                systemImage: book.isAvailable ? "checkmark.circle.fill" : "clock.fill"
                            )
                            .foregroundStyle(book.isAvailable ? .green : .orange)

                            Spacer()

                            if book.isAvailable {
                                if hasPendingRequest {
                                    Button(action: {}) {
                                        Label("Requested", systemImage: "clock.badge.checkmark")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.indigo)
                                    .disabled(true)
                                } else {
                                    Button("Request to Borrow") {
                                        showingRequestSheet = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.indigo)
                                }
                            }
                        }
                    }

                    if let notes = book.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.headline)
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Requests section
                    let bookRequests = (book.requests as? Set<CDBookRequest>)?.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    } ?? []
                    if !bookRequests.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requests")
                                .font(.headline)
                            ForEach(bookRequests) { request in
                                RequestRow(request: request, isOwner: isOwner)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner && !isBorrowedCopy {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditSheet = true }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditBookSheet(book: book)
        }
        .sheet(isPresented: $showingRequestSheet) {
            RequestBorrowSheet(book: book)
        }
    }
}

struct RequestRow: View {
    @ObservedObject var request: CDBookRequest
    let isOwner: Bool
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(request.requesterName ?? "Someone")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let message = request.message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(status: request.status ?? "pending")
            }

            if isOwner && request.status == "pending" {
                HStack(spacing: 12) {
                    Button("Approve") {
                        request.status = "approved"
                        request.book?.isAvailable = false
                        try? viewContext.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Decline") {
                        request.status = "declined"
                        try? viewContext.save()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .font(.subheadline)
            }

            if let date = request.createdAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditBookSheet: View {
    @ObservedObject var book: CDBook
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Info") {
                    TextField("Title", text: Binding(
                        get: { book.title ?? "" },
                        set: { book.title = $0 }
                    ))
                    TextField("Author", text: Binding(
                        get: { book.author ?? "" },
                        set: { book.author = $0 }
                    ))
                    TextField("Genre", text: Binding(
                        get: { book.genre ?? "" },
                        set: { book.genre = $0 }
                    ))
                    TextField("ISBN", text: Binding(
                        get: { book.isbn ?? "" },
                        set: { book.isbn = $0 }
                    ))
                }
                Section("Details") {
                    TextField("Publish Year", text: Binding(
                        get: { book.publishYear ?? "" },
                        set: { book.publishYear = $0 }
                    ))
                    Stepper("Pages: \(book.pageCount)", value: Binding(
                        get: { book.pageCount },
                        set: { book.pageCount = $0 }
                    ), in: 0...10000, step: 10)
                }
                Section("Notes") {
                    TextField("Notes", text: Binding(
                        get: { book.notes ?? "" },
                        set: { book.notes = $0 }
                    ), axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? viewContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RequestBorrowSheet: View {
    let book: CDBook
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.persistenceController) private var persistence
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLibrary.createdAt, ascending: true)]
    ) private var allLibraries: FetchedResults<CDLibrary>

    @State private var selectedLibrary: CDLibrary?
    @State private var message = ""

    private var myLibraries: [CDLibrary] {
        allLibraries.filter { persistence.isOwner($0) && $0.name != "Borrowed" }
    }

    private var requesterName: String {
        guard let library = selectedLibrary else { return "" }
        let owner = (library.ownerName ?? "").trimmingCharacters(in: .whitespaces)
        return owner.isEmpty ? (library.name ?? "") : owner
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Requesting as") {
                    if myLibraries.isEmpty {
                        Text("Create a library first so the owner knows who's asking.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Library", selection: $selectedLibrary) {
                            ForEach(myLibraries) { library in
                                Text(libraryLabel(library)).tag(Optional(library))
                            }
                        }
                    }
                }
                Section("Message (optional)") {
                    TextField("Why you'd like to borrow this book", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Request to Borrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        let request = CDBookRequest(context: viewContext)
                        request.requesterName = requesterName
                        request.requesterLibraryName = selectedLibrary?.name
                        request.message = message.trimmingCharacters(in: .whitespaces)
                        request.status = "pending"
                        request.createdAt = Date()
                        request.book = book
                        try? viewContext.save()
                        dismiss()
                    }
                    .disabled(selectedLibrary == nil || requesterName.isEmpty)
                }
            }
            .onAppear {
                if selectedLibrary == nil {
                    selectedLibrary = myLibraries.first
                }
            }
        }
    }

    private func libraryLabel(_ library: CDLibrary) -> String {
        let name = library.name ?? "Untitled"
        let owner = (library.ownerName ?? "").trimmingCharacters(in: .whitespaces)
        return owner.isEmpty ? name : "\(name) — \(owner)"
    }
}
