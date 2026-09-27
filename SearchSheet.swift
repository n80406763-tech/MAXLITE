import SwiftUI

struct SearchSheet: View {
    let chatId: Int64
    @EnvironmentObject var client: MaxClient
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Message] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if searching {
                    ProgressView().frame(maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("Ошибка поиска", systemImage: "exclamationmark.triangle",
                                          description: Text(error))
                } else if results.isEmpty {
                    ContentUnavailableView("Поиск по чату", systemImage: "magnifyingglass",
                                          description: Text("Введите слово или фразу."))
                } else {
                    List(results) { m in
                        VStack(alignment: .leading, spacing: 3) {
                            if !m.senderName.isEmpty {
                                Text(m.senderName).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            }
                            Text(m.text.isEmpty ? (m.attachments.first?.label ?? "…") : m.text)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await run() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        do {
            results = try await client.searchMessages(q, in: chatId)
        } catch {
            self.error = error.localizedDescription
        }
        searching = false
    }
}
