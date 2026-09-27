import SwiftUI

/// Менеджер тем оформления
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: Theme = .system {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system = "Системная"
        case light = "Светлая"
        case dark = "Тёмная"
        case amoled = "AMOLED"

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark, .amoled: return .dark
            }
        }

        var isAmoled: Bool { self == .amoled }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = Theme(rawValue: saved) {
            currentTheme = theme
        }
    }
}

/// Модификатор для применения темы
struct ThemedBackground: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .background(
                themeManager.currentTheme.isAmoled
                    ? Color.black.ignoresSafeArea()
                    : Color.clear.ignoresSafeArea()
            )
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}

/// Акцентный цвет для пузырей сообщений
enum BubbleColor: String, CaseIterable, Identifiable {
    case blue = "Синий"
    case green = "Зелёный"
    case purple = "Фиолетовый"
    case pink = "Розовый"
    case orange = "Оранжевый"
    case red = "Красный"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .red: return .red
        }
    }
}

final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    @Published var bubbleColor: BubbleColor = .blue {
        didSet {
            UserDefaults.standard.set(bubbleColor.rawValue, forKey: "bubbleColor")
        }
    }

    @Published var fontSize: FontSize = .medium {
        didSet {
            UserDefaults.standard.set(fontSize.rawValue, forKey: "fontSize")
        }
    }

    enum FontSize: String, CaseIterable, Identifiable {
        case small = "Мелкий"
        case medium = "Средний"
        case large = "Крупный"
        case extraLarge = "Очень крупный"

        var id: String { rawValue }

        var scale: CGFloat {
            switch self {
            case .small: return 0.9
            case .medium: return 1.0
            case .large: return 1.15
            case .extraLarge: return 1.3
            }
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "bubbleColor"),
           let color = BubbleColor(rawValue: saved) {
            bubbleColor = color
        }
        if let saved = UserDefaults.standard.string(forKey: "fontSize"),
           let size = FontSize(rawValue: saved) {
            fontSize = size
        }
    }
}
