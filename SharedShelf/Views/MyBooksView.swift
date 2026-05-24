import SwiftUI
import CoreData

struct MyBooksView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var library: CDLibrary
    let isOwner: Bool
    @State private var showingAddBook = false
    @State private var searchText = ""
    @State private var selectedGenre = "All"

    private var books: [CDBook] {
        let allBooks = (library.books as? Set<CDBook>)?.sorted {
            ($0.title ?? "") .localizedCompare($1.title ?? "") == .orderedAscending
        } ?? []
        return allBooks
    }

    private var genres: [String] {
        let allGenres = Set(books.compactMap { $0.genre }).filter { !$0.isEmpty }
        return ["All"] + allGenres.sorted()
    }

    private var filteredBooks: [CDBook] {
        books.filter { book in
            let matchesSearch = searchText.isEmpty ||
                (book.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                (book.author ?? "").localizedCaseInsensitiveContains(searchText) ||
                (book.isbn ?? "").contains(searchText)
            let matchesGenre = selectedGenre == "All" || book.genre == selectedGenre
            return matchesSearch && matchesGenre
        }
    }

    var body: some View {
        booksContent
            .navigationTitle(library.name ?? "Library")
            .searchable(text: $searchText, prompt: "Search by title, author, or ISBN")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingAddBook = true }) {
                        Image(systemName: "plus")
                    }
                    .opacity(isOwner ? 1 : 0)
                    .disabled(!isOwner)
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Text(books.isEmpty ? "" : "\(books.count) book\(books.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingAddBook) {
                AddBookView(library: library)
            }
    }

    @ViewBuilder
    private var booksContent: some View {
        if books.isEmpty {
            ContentUnavailableView(
                "No Books Yet",
                systemImage: "book.closed",
                description: Text(isOwner
                    ? "Tap + to add your first book, or scan a barcode."
                    : "This library is empty.")
            )
        } else if filteredBooks.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            booksList
        }
    }

    private var booksList: some View {
        List {
            ForEach(filteredBooks) { book in
                NavigationLink(destination: BookDetailView(book: book, isOwner: isOwner)) {
                    BookRow(book: book)
                }
            }
            .onDelete { offsets in
                guard isOwner else { return }
                let booksToDelete = offsets.map { filteredBooks[$0] }
                for book in booksToDelete { viewContext.delete(book) }
                try? viewContext.save()
            }
        }
    }

    private func deleteBooks(at offsets: IndexSet) {
        let booksToDelete = offsets.map { filteredBooks[$0] }
        for book in booksToDelete {
            viewContext.delete(book)
        }
        try? viewContext.save()
    }
}

struct BookRow: View {
    @ObservedObject var book: CDBook

    var body: some View {
        HStack(spacing: 12) {
            if let imageData = book.coverImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.indigo.opacity(0.15))
                    .frame(width: 50, height: 70)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.indigo)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(2)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let owner = book.ownerName, !owner.isEmpty, owner != "Me" {
                    Text("From: \(owner)")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                HStack(spacing: 8) {
                    if let genre = book.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.indigo.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if !book.isAvailable {
                        Text("Lent Out")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
