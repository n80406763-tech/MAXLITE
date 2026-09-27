import SwiftUI

/// Индикатор непрочитанных сообщений для чата
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count > 99 ? "99+" : "\(count)")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 6 : 7)
                .padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
        }
    }
}

/// Кастомный тап-гестюр для двойного нажатия (лайк сообщения)
struct DoubleTapGesture: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) {
                action()
            }
    }
}

extension View {
    func onDoubleTap(perform action: @escaping () -> Void) -> some View {
        modifier(DoubleTapGesture(action: action))
    }
}

/// Эффект "печатает..." с анимированными точками
struct TypingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack(spacing: 4) {
            Text("печатает")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 3, height: 3)
                        .opacity(dotCount > index ? 1 : 0.3)
                }
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

/// Быстрая реакция на сообщение (долгий тап)
struct QuickReactionOverlay: View {
    let reactions = ["👍", "❤️", "😂", "😮", "😢", "🔥"]
    let onReact: (String) -> Void
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            HStack(spacing: 12) {
                ForEach(reactions, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                        isPresented = false
                    } label: {
                        Text(emoji)
                            .font(.title)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 8)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Компактный индикатор онлайн-статуса
struct OnlineIndicator: View {
    let isOnline: Bool

    var body: some View {
        Circle()
            .fill(isOnline ? Color.green : Color.gray)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 2)
            )
    }
}

/// Анимация отправки сообщения
struct SendingAnimation: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 0.8
                    opacity = 0
                }
            }
    }
}

extension View {
    func sendingAnimation() -> some View {
        modifier(SendingAnimation())
    }
}

/// Кастомная прогресс-бар для загрузки файлов
struct FileUploadProgress: View {
    let progress: Double
    let filename: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                Text(filename)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.tertiarySystemFill))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
