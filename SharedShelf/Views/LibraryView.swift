import SwiftUI

struct LibraryView: View {
    var body: some View {
        TabView {
            Tab("My Libraries", systemImage: "books.vertical") {
                LibrariesListView(shared: false)
            }
            Tab("Shared", systemImage: "person.2") {
                LibrariesListView(shared: true)
            }
            Tab("Requests", systemImage: "arrow.left.arrow.right") {
                RequestsView()
            }
        }
        .tint(.indigo)
    }
}
