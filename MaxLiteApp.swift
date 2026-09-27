import SwiftUI
import UserNotifications

@main
struct MaxLiteApp: App {
    @StateObject private var client = MaxClient()
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var callManager: CallManager

    init() {
        let client = MaxClient()
        _client = StateObject(wrappedValue: client)
        _callManager = StateObject(wrappedValue: CallManager(client: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(callManager)
                .themedBackground()
                .overlay {
                    // Входящий звонок поверх всего
                    if let incoming = callManager.incomingCall {
                        IncomingCallView(
                            call: incoming,
                            onAnswer: { Task { try? await callManager.answerCall() } },
                            onDecline: { Task { await callManager.declineCall() } }
                        )
                        .transition(.move(edge: .bottom))
                    }
                    // Активный звонок поверх всего
                    else if let active = callManager.activeCall {
                        ActiveCallView(
                            call: active,
                            onMute: { callManager.toggleMute() },
                            onSpeaker: { callManager.toggleSpeaker() },
                            onVideo: { callManager.toggleVideo() },
                            onHangup: { Task { await callManager.endCall() } }
                        )
                        .transition(.move(edge: .bottom))
                    }
                }
                .animation(.easeInOut, value: callManager.incomingCall != nil)
                .animation(.easeInOut, value: callManager.activeCall != nil)
                .onAppear {
                    client.start()
                    if AppSettings.shared.notificationsOn {
                        UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var client: MaxClient
    @State private var showLogin = false
    @AppStorage("disclaimerSeen") private var disclaimerSeen = false

    var body: some View {
        Group {
            if client.auth == nil {
                WelcomeView(showLogin: $showLogin)
            } else {
                ChatListView()
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView { auth in
                Keychain.save(auth)
                client.auth = auth
                showLogin = false
            }
        }
        // Дисклеймер — до первого входа, поверх всего остального, закрыть
        // нельзя иначе как кнопкой.
        .fullScreenCover(isPresented: .constant(!disclaimerSeen)) {
            DisclaimerSheet { disclaimerSeen = true }
        }
    }
}

struct WelcomeView: View {
    @Binding var showLogin: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("MAX Lite")
                .font(.largeTitle.bold())
            Text("Чаты, группы и каналы вашего аккаунта MAX.\nВход — обычный, на сайте MAX.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                showLogin = true
            } label: {
                Text("Войти в MAX")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            Text("Приложение открывает настоящий сайт MAX. Логин и код\nиз SMS вводятся там же; приложению они не передаются.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
        }
    }
}
