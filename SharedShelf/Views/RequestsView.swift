import SwiftUI
import CoreData

struct RequestsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDBookRequest.createdAt, ascending: false)]
    ) private var requests: FetchedResults<CDBookRequest>

    var body: some View {
        NavigationStack {
            Group {
                if requests.isEmpty {
                    ContentUnavailableView(
                        "No Requests",
                        systemImage: "tray",
                        description: Text("When someone requests one of your books, it will appear here.")
                    )
                } else {
                    List {
                        let pending = requests.filter { $0.status == "pending" }
                        let resolved = requests.filter { $0.status != "pending" }

                        if !pending.isEmpty {
                            Section("Pending") {
                                ForEach(pending) { request in
                                    RequestManageRow(request: request)
                                }
                            }
                        }

                        if !resolved.isEmpty {
                            Section("Resolved") {
                                ForEach(resolved) { request in
                                    RequestManageRow(request: request)
                                }
                                .onDelete { offsets in
                                    let toDelete = offsets.map { resolved[$0] }
                                    for r in toDelete { viewContext.delete(r) }
                                    try? viewContext.save()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Requests")
        }
    }
}

struct RequestManageRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.persistenceController) private var persistence
    @ObservedObject var request: CDBookRequest

    private var isOwner: Bool {
        guard let book = request.book else { return false }
        return persistence.isOwner(book)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(request.book?.title ?? "Unknown Book")
                        .font(.headline)
                    Text("From: \(request.requesterName ?? "Someone")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: request.status ?? "pending")
            }

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case "approved": return .green
        case "declined": return .red
        case "returned": return .gray
        default: return .orange
        }
    }
}
