import SwiftUI

/// Пересылка реализована на стороне приложения: копия текста уходит в
/// выбранный чат обычным MSG_SEND, с подписью "Переслано от …". Нативный
/// FORWARD_MESSAGE(70) в протоколе задокументирован ненадёжно — по
/// наблюдениям авторов реверс-инжиниринга он не всегда переносит сообщение,
/// поэтому здесь используется гарантированно рабочий путь.
struct ForwardPicker: View {
    let text: String
    let attachments: [Attachment]
    let fromAuthor: String
    @EnvironmentObject var client: MaxClient
    @Environment(\.dismiss) private var dismiss
    @State private var sendingTo: Int64?
    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            List(client.chats) { chat in
                Button {
                    Task { await forward(to: chat) }
                } label: {
                    HStack {
                        ChatRow(chat: chat)
                        Spacer()
                        if sendingTo == chat.id {
                            ProgressView()
                        }
                    }
                }
                .disabled(sendingTo != nil)
            }
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Не удалось переслать", isPresented: errorBinding) {
                Button("ОК") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func forward(to chat: Chat) async {
        sendingTo = chat.id
        defer { sendingTo = nil }
        var body = text
        if body.isEmpty, let a = attachments.first {
            body = "[\(a.label)]"
        }
        let composed = "↪️ Переслано от \(fromAuthor):\n\(body)"
        do {
            try await client.send(composed, to: chat.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
