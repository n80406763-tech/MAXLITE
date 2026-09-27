import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var client: MaxClient
    @ObservedObject private var s = AppSettings.shared
    @StateObject private var ip = IPCheck()
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Группы", isOn: $s.showGroups)
                    Toggle("Каналы", isOn: $s.showChannels)
                    Toggle("Личные чаты", isOn: $s.showDialogs)
                } header: {
                    Text("Что показывать")
                } footer: {
                    Text("Выключите лишнее, чтобы остались только группы.")
                }

                Section {
                    Toggle("Показывать картинки", isOn: $s.showImages)
                    Toggle("Скрывать события звонков", isOn: $s.hideCallEvents)
                    Toggle("Автозагрузка медиа", isOn: $s.autoDownloadMedia)
                } header: {
                    Text("Содержимое")
                } footer: {
                    Text("Звонков в приложении нет — можно только спрятать записи о них в переписке.")
                }

                Section {
                    Toggle("Режим невидимки", isOn: $s.stealthMode)
                    Toggle("Debug режим", isOn: $s.debugMode)
                        .onChange(of: s.debugMode) { _, enabled in
                            if enabled {
                                Task { await client.reloadAllChats() }
                            }
                        }
                } header: {
                    Text("Приватность")
                } footer: {
                    Text("В режиме невидимки вы не отправляете индикатор \"печатает\" и не запрашиваете статус \"в сети\" других пользователей. Для остальных вы будете выглядеть как \"не в сети\".\n\nDebug режим сохраняет raw JSON от сервера — при включении перезагрузит все чаты.")
                }

                Section {
                    Picker("Тема", selection: $themeManager.currentTheme) {
                        ForEach(ThemeManager.Theme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    Picker("Цвет пузырей", selection: $appearanceManager.bubbleColor) {
                        ForEach(BubbleColor.allCases) { color in
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 20, height: 20)
                                Text(color.rawValue)
                            }
                            .tag(color)
                        }
                    }

                    Picker("Размер текста", selection: $appearanceManager.fontSize) {
                        ForEach(AppearanceManager.FontSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                } header: {
                    Text("Оформление")
                }

                Section {
                    Toggle("Уведомления о сообщениях", isOn: $s.notificationsOn)
                } header: {
                    Text("Уведомления")
                } footer: {
                    Text("Локальные уведомления. Приходят, пока приложение запущено или недавно свёрнуто: iOS усыпляет фоновые соединения, а настоящий push потребовал бы своего сервера и платного аккаунта разработчика.")
                }

                Section {
                    Toggle("Проверять страну IP", isOn: $s.ipCheckOn)
                    if let r = ip.result {
                        LabeledContent("Адрес", value: r.ip)
                        LabeledContent("Видны как", value: r.country)
                        Label(
                            r.isRussian ? "Российский адрес" : "Иностранный адрес",
                            systemImage: r.isRussian ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(r.isRussian ? .green : .orange)
                    } else if ip.checking {
                        HStack { ProgressView(); Text("Проверяю…").foregroundStyle(.secondary) }
                    } else if let e = ip.error {
                        Text(e).foregroundStyle(.secondary)
                    }
                    Button("Проверить сейчас") { Task { await ip.refresh() } }
                        .disabled(ip.checking)
                } header: {
                    Text("Сеть и адрес")
                } footer: {
                    ipFooter
                }

                Section {
                    NavigationLink("Заблокированные пользователи") {
                        BlockedUsersView()
                    }
                    NavigationLink("Архивные чаты") {
                        ArchivedChatsView()
                    }
                } header: {
                    Text("Дополнительно")
                }

                Section {
                    Button("Выйти из аккаунта", role: .destructive) { confirmSignOut = true }
                }

                Section {
                    NavigationLink("О приложении") { AboutView() }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task { if s.ipCheckOn { await ip.refresh() } }
            .confirmationDialog("Выйти?", isPresented: $confirmSignOut) {
                Button("Выйти", role: .destructive) { client.signOut(); dismiss() }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Токен будет удалён с устройства.")
            }
        }
    }

    /// Формулировка намеренно нейтральная: спрятать IP приложение не может,
    /// а «выключить VPN» — это не защита, а размен одного риска на другой.
    private var ipFooter: Text {
        if let r = ip.result, !r.isRussian {
            return Text("""
            Сейчас MAX видит адрес в стране \(r.code). Вход с иностранного IP \
            иногда приводит к блокировке аккаунта — если это важно, выключите VPN.

            Учтите обратную сторону: без VPN MAX увидит ваш настоящий домашний \
            адрес и провайдера. С VPN он видит адрес VPN-сервера. Спрятать IP \
            изнутри приложения нельзя — это делается только на уровне системы.
            """)
        }
        return Text("""
        Приложение не может скрыть ваш IP: это умеет только VPN или прокси в \
        настройках iOS. Здесь показано лишь то, каким вас видит сервер.
        """)
    }
}
