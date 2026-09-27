import SwiftUI

/// Экран входящего звонка
struct IncomingCallView: View {
    let call: CallManager.IncomingCall
    let onAnswer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                    Text(call.fromUserName)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text(call.isVideo ? "Видеозвонок…" : "Звонок…")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                HStack(spacing: 80) {
                    // Отклонить
                    Button {
                        onDecline()
                    } label: {
                        Circle()
                            .fill(.red)
                            .frame(width: 70, height: 70)
                            .overlay {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white)
                            }
                    }

                    // Принять
                    Button {
                        onAnswer()
                    } label: {
                        Circle()
                            .fill(.green)
                            .frame(width: 70, height: 70)
                            .overlay {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }
}

/// Экран активного звонка
struct ActiveCallView: View {
    let call: CallManager.ActiveCall
    let onMute: () -> Void
    let onSpeaker: () -> Void
    let onVideo: () -> Void
    let onHangup: () -> Void

    @State private var callDuration = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                    Text(call.userName)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text(formatDuration(callDuration))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Кнопки управления
                HStack(spacing: 30) {
                    // Микрофон
                    Button {
                        onMute()
                    } label: {
                        Circle()
                            .fill(call.isMuted ? .red : Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                            }
                    }

                    // Динамик
                    Button {
                        onSpeaker()
                    } label: {
                        Circle()
                            .fill(call.isSpeaker ? .blue : Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                            }
                    }

                    // Видео (только для видеозвонков)
                    if call.isVideo {
                        Button {
                            onVideo()
                        } label: {
                            Circle()
                                .fill(call.isVideoEnabled ? .blue : Color.white.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Image(systemName: call.isVideoEnabled ? "video.fill" : "video.slash.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                }

                // Завершить звонок
                Button {
                    onHangup()
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 70, height: 70)
                        .overlay {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }
                }
                .padding(.top, 20)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                callDuration += 1
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
