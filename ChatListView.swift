import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var client: MaxClient
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var showSettings = false
    @State private var showCreateGroup = false
    @State private var path: [Chat] = []

    private var visible: [Chat] {
        var list = client.chats.filter { settings.allows($0.kind) }
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if visible.isEmpty {
                    ContentUnavailableView(
                        !client.online
                            ? "Подключение…"
                            : (query.isEmpty ? "Чатов пока нет" : "Ничего не найдено"),
                        systemImage: !client.online
                            ? "arrow.triangle.2.circlepath"
                            : (query.isEmpty ? "tray" : "magnifyingglass"),
                        description: Text(!client.online
                            ? client.status
                            : (query.isEmpty
                                ? "Список придёт после авторизации. Если чаты есть, а списка нет — проверьте типы чатов в настройках."
                                : "Измените запрос или сбросьте фильтры в настройках."))
                    )
                } else {
                    List(visible) { chat in
                        NavigationLink(value: chat) {
                            ChatRow(chat: chat)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: "Поиск")
                }
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatView(chat: chat)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Заголовок с индикатором подключения под ним — раньше точка
                // и статус были в узкой левой части панели и текст обрезался.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Чаты").font(.headline)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(client.online ? .green : .red)
                                .frame(width: 6, height: 6)
                            Text(client.online ? (client.myName.isEmpty ? "в сети" : client.myName) : client.status)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreateGroup = true
                        } label: {
                            Label("Новая группа", systemImage: "person.3.fill")
                        }

                        Divider()

                        Button {
                            showSettings = true
                        } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable { await client.refreshChats() }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(client)
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet().environmentObject(client)
            }
            // Переход по чату из глубины стека (тап по «переслано от …»):
            // selectChat/openDialogWith теперь выставляют client.pendingChatId,
            // здесь он превращается в реальный push в навигацию.
            .onChange(of: client.pendingChatId) { _, newValue in
                guard let id = newValue else { return }
                if let chat = client.chats.first(where: { $0.id == id }) {
                    path = [chat]
                }
                client.pendingChatId = nil
            }
        }
        // Опрос раз в 20 с нужен, пока открыт список чатов. Как только
        // пользователь ушёл в переписку, `.task` отменяется и не перезапускается
        // при возврате (родитель остаётся в стеке) — двойных запросов нет.
        .task {
            while !Task.isCancelled {
                await client.refreshChats()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        // При возврате из чата список обновляем один раз, а не заново циклом.
        .onChange(of: path.isEmpty) { _, isRoot in
            guard isRoot else { return }
            Task { await client.refreshChats() }
        }
    }
}

extension Chat: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChatRow: View {
    let chat: Chat
    @ObservedObject private var unreadManager = UnreadManager.shared

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(chat.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let count = unreadManager.unreadCounts[chat.id], count > 0 {
                UnreadBadge(count: count)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var avatar: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
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
        .frame(width: 40, height: 40)
    }
}
