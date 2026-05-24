import SwiftUI
import CoreData

struct AddBookView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let library: CDLibrary

    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var genre = ""
    @State private var notes = ""
    @State private var pageCount = 0
    @State private var publishYear = ""
    @State private var coverImageData: Data?

    @State private var showingScanner = false
    @State private var isLookingUp = false
    @State private var lookupError: String?

    private let genreOptions = [
        "", "Fiction", "Non-Fiction", "Mystery", "Science Fiction", "Fantasy",
        "Biography", "History", "Science", "Self-Help", "Business",
        "Poetry", "Romance", "Thriller", "Horror", "Children's",
        "Cooking", "Travel", "Art", "Religion", "Philosophy", "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // ISBN Scanner section
                Section {
                    Button(action: { showingScanner = true }) {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .tint(.indigo)

                    HStack {
                        TextField("Or enter ISBN", text: $isbn)
                            .keyboardType(.numberPad)
                        if !isbn.isEmpty {
                            Button("Look Up") {
                                Task { await lookupISBN() }
                            }
                            .disabled(isLookingUp)
                        }
                    }

                    if isLookingUp {
                        HStack {
                            ProgressView()
                            Text("Looking up book...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = lookupError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Quick Add")
                }

                // Cover preview
                if let imageData = coverImageData,
                   let uiImage = UIImage(data: imageData) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                        }
                        Button("Remove Cover", role: .destructive) {
                            self.coverImageData = nil
                        }
                    }
                }

                // Manual entry
                Section("Book Info") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    Picker("Genre", selection: $genre) {
                        ForEach(genreOptions, id: \.self) { g in
                            Text(g.isEmpty ? "None" : g).tag(g)
                        }
                    }
                }

                Section("Details") {
                    TextField("Publish Year", text: $publishYear)
                    Stepper("Pages: \(pageCount)", value: $pageCount, in: 0...10000, step: 10)
                }

                Section("Notes") {
                    TextField("Personal notes about this book", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBook()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { scannedISBN in
                    isbn = scannedISBN
                    showingScanner = false
                    Task { await lookupISBN() }
                }
            }
        }
    }

    private func saveBook() {
        let book = CDBook(context: viewContext)
        book.title = title.trimmingCharacters(in: .whitespaces)
        book.author = author.trimmingCharacters(in: .whitespaces)
        book.isbn = isbn.trimmingCharacters(in: .whitespaces)
        book.genre = genre
        book.notes = notes.trimmingCharacters(in: .whitespaces)
        book.coverImageData = coverImageData
        book.pageCount = Int32(pageCount)
        book.publishYear = publishYear
        book.isAvailable = true
        book.ownerName = library.ownerName ?? "Me"
        book.createdAt = Date()
        book.library = library
        try? viewContext.save()
    }

    private func lookupISBN() async {
        #if DEBUG
        print("ISBN_LOOKUP: starting lookup for '\(isbn)'")
        #endif
        isLookingUp = true
        lookupError = nil
        do {
            let result = try await ISBNLookupService.lookup(isbn: isbn)
            #if DEBUG
            print("ISBN_LOOKUP: success — title='\(result.title)', author='\(result.author)', pages=\(result.pageCount)")
            #endif
            title = result.title
            author = result.author
            publishYear = result.publishYear
            pageCount = result.pageCount
            if let coverURL = result.coverURL {
                #if DEBUG
                print("ISBN_LOOKUP: fetching cover \(coverURL)")
                #endif
                coverImageData = await ISBNLookupService.fetchCoverImage(urlString: coverURL)
            }
        } catch {
            #if DEBUG
            print("ISBN_LOOKUP: ERROR — \(error)  localized='\(error.localizedDescription)'")
            #endif
            lookupError = error.localizedDescription
        }
        isLookingUp = false
    }
}
