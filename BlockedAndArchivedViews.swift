import SwiftUI

/// Список заблокированных пользователей
struct BlockedUsersView: View {
    @EnvironmentObject var client: MaxClient
    @State private var blockedUsers: [BlockedUser] = []
    @State private var loading = true
    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        List {
            if loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if blockedUsers.isEmpty {
                ContentUnavailableView(
                    "Нет заблокированных",
                    systemImage: "hand.raised.slash",
                    description: Text("Заблокированные пользователи появятся здесь")
                )
            } else {
                ForEach(blockedUsers) { user in
                    HStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill.xmark")
                                    .foregroundStyle(.red)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.body)
                            Text("Заблокирован")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            Task { await unblock(user.userId) }
                        } label: {
                            Text("Разблокировать")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Заблокированные")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ошибка", isPresented: errorBinding) {
            Button("ОК") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task {
            await loadBlockedUsers()
        }
    }

    private func loadBlockedUsers() async {
        loading = true
        defer { loading = false }

        // TODO: Загрузить через опкод GET_BLOCKED_USERS (ExtendedOp.getBlockedUsers)
        // Пока заглушка
        blockedUsers = []
    }

    private func unblock(_ userId: Int64) async {
        do {
            try await client.unblockUser(userId: userId)
            await loadBlockedUsers()
        } catch {
            self.error = error.localizedDescription
        }
    }

    struct BlockedUser: Identifiable {
        let id: Int64
        let userId: Int64
        let name: String
    }
}

/// Список архивных чатов
struct ArchivedChatsView: View {
    @EnvironmentObject var client: MaxClient
    @State private var archivedChats: [Chat] = []
    @State private var loading = true
    @State private var error: String?
    private var errorBindingArchived: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        List {
            if loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if archivedChats.isEmpty {
                ContentUnavailableView(
                    "Архив пуст",
                    systemImage: "archivebox",
                    description: Text("Архивированные чаты появятся здесь")
                )
            } else {
                ForEach(archivedChats) { chat in
                    HStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if let url = chat.iconURL {
                                    AsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Text(chat.initial).font(.headline).foregroundStyle(.tint)
                                    }
                                    .clipShape(Circle())
                                } else {
                                    Text(chat.initial).font(.headline).foregroundStyle(.tint)
                                }
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title)
                                .font(.body.weight(.semibold))
                            Text(chat.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            Task { await unarchive(chat.id) }
                        } label: {
                            Image(systemName: "arrow.up.bin")
                        }
                    }
                }
            }
        }
        .navigationTitle("Архив")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ошибка", isPresented: errorBindingArchived) {
            Button("ОК") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task {
            await loadArchivedChats()
        }
    }

    private func loadArchivedChats() async {
        loading = true
        defer { loading = false }

        // TODO: Загрузить через опкод GET_ARCHIVED_CHATS (ExtendedOp.getArchivedChats)
        // Пока заглушка
        archivedChats = []
    }

    private func unarchive(_ chatId: Int64) async {
        // TODO: Разархивировать через опкод UNARCHIVE_CHAT (ExtendedOp.unarchiveChat)
        await loadArchivedChats()
    }
}
