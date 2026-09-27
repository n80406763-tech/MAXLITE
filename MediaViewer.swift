import SwiftUI
import AVKit

/// Полноэкранный просмотр фото или видео из чата, с сохранением в галерею.
struct MediaViewer: View {
    let url: URL
    let isVideo: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?
    @State private var savedOK = false
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isVideo {
                    VideoPlayer(player: AVPlayer(url: url))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            case .failure: ContentUnavailableView("Не загрузилось", systemImage: "photo")
                            default: ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }.tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() }
                        else { Image(systemName: savedOK ? "checkmark.circle.fill" : "square.and.arrow.down") }
                    }
                    .tint(.white)
                    .disabled(saving)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .alert("Не сохранилось", isPresented: errorBinding) {
            Button("ОК") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if isVideo { try await MediaSaver.saveVideo(from: url) }
            else { try await MediaSaver.savePhoto(from: url) }
            savedOK = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
