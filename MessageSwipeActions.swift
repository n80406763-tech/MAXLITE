import SwiftUI

/// Быстрые действия с сообщением через свайп
struct MessageSwipeActions: ViewModifier {
    let message: Message
    let isMine: Bool
    let onReply: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onForward: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    onReply()
                } label: {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }

                if let onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                    .tint(.orange)
                }

                Button {
                    onForward()
                } label: {
                    Label("Переслать", systemImage: "arrowshape.turn.up.right")
                }
                .tint(.green)
            }
    }
}

extension View {
    func messageSwipeActions(
        message: Message,
        isMine: Bool,
        onReply: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onForward: @escaping () -> Void
    ) -> some View {
        modifier(MessageSwipeActions(
            message: message,
            isMine: isMine,
            onReply: onReply,
            onEdit: onEdit,
            onDelete: onDelete,
            onForward: onForward
        ))
    }
}
