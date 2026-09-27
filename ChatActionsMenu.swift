import SwiftUI

/// Расширенное меню чата с дополнительными функциями
struct ChatActionsMenu: View {
    let chat: Chat
    @EnvironmentObject var client: MaxClient

    @State private var showLocationPicker = false
    @State private var showPollCreator = false
    @State private var showGroupSettings = false

    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        Menu {
            // Геолокация
            Button {
                showLocationPicker = true
            } label: {
                Label("Отправить геолокацию", systemImage: "location.fill")
            }

            // Опрос (только для групп/каналов)
            if chat.kind == .chat || chat.kind == .channel {
                Button {
                    showPollCreator = true
                } label: {
                    Label("Создать опрос", systemImage: "chart.bar.fill")
                }
            }

            Divider()

            // Управление группой
            if chat.kind == .chat {
                Button {
                    showGroupSettings = true
                } label: {
                    Label("Настройки группы", systemImage: "gearshape.fill")
                }

                Button(role: .destructive) {
                    Task { await leaveGroup() }
                } label: {
                    Label("Выйти из группы", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            // Архивация: реальный опкод сервера не подтверждён — кнопка остаётся,
            // но честно сообщает об этом при нажатии, а не «делает вид».
            Button {
                Task { await archiveChat() }
            } label: {
                Label("Архивировать чат", systemImage: "archivebox.fill")
            }

        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet(chatId: chat.id)
                .environmentObject(client)
        }
        .sheet(isPresented: $showPollCreator) {
            CreatePollSheet(chatId: chat.id)
                .environmentObject(client)
        }
        .sheet(isPresented: $showGroupSettings) {
            GroupSettingsView(chat: chat)
                .environmentObject(client)
        }
        .alert("Ошибка", isPresented: errorBinding) {
            Button("ОК") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func archiveChat() async {
        // Не трогает локальное состояние: пока нет реального опкода, ничего
        // не меняем — ни непрочитанных, ни архива. Просто показываем ошибку.
        error = "Архивация в этой версии недоступна: опкод сервера не подтверждён."
    }

    private func leaveGroup() async {
        do {
            try await client.leaveGroup(chatId: chat.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Настройки группы: участники, администрирование
struct GroupSettingsView: View {
    let chat: Chat
    @EnvironmentObject var client: MaxClient
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(chat.title)
                        .font(.headline)
                    if !chat.subtitle.isEmpty {
                        Text(chat.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Информация")
                }

                Section {
                    // Список участников не показываем вовсе: опкод для него
                    // неизвестен, а «Нет участников» на живом чате выглядит как
                    // поломка. Честнее сказать прямо.
                    Text("Список участников в этой версии недоступен: серверный опкод для него пока не определён.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Участники")
                }
            }
            .navigationTitle("Настройки группы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("ОК") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }
}
