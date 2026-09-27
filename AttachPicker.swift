import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Кнопка "+" рядом с полем ввода: фото/видео из галереи или произвольный
/// файл. Поддерживает множественный выбор и предпросмотр фото перед отправкой.
struct AttachPicker: View {
    var onPick: (Data, String, String) -> Void   // data, filename, mimeType
    @ObservedObject private var settings = AppSettings.shared
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showPhotoPreview = false
    @State private var busy = false
    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
    @State private var previewImage: UIImage?
    @State private var previewData: Data?
    @State private var previewFilename: String = ""
    @State private var previewMimeType: String = ""

    var body: some View {
        Menu {
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                Label("Фото или видео", systemImage: "photo")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Файл", systemImage: "doc")
            }
        } label: {
            if busy {
                ProgressView().frame(width: 24, height: 24)
            } else {
                Image(systemName: "plus.circle.fill").font(.system(size: 24))
            }
        }
        .disabled(busy)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): Task { await loadFile(url) }
            case .failure(let e): error = e.localizedDescription
            }
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let img = previewImage {
                PhotoPreviewSheet(
                    image: img,
                    onSend: {
                        onPick(previewData!, previewFilename, previewMimeType)
                        showPhotoPreview = false
                        previewImage = nil
                    },
                    onCancel: {
                        showPhotoPreview = false
                        previewImage = nil
                    }
                )
            }
        }
        .alert("Не удалось прикрепить файл", isPresented: errorBinding) {
            Button("ОК") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false; photoItems = [] }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                error = "Не получилось прочитать файл"
                continue
            }
            let utType = item.supportedContentTypes.first
            let ext = utType?.preferredFilenameExtension ?? "jpg"
            let mime = utType?.preferredMIMEType ?? "application/octet-stream"

            // Если это картинка - показываем превью (только для первого)
            if mime.hasPrefix("image/"), let img = UIImage(data: data) {
                previewImage = img
                previewData = data
                previewFilename = "photo.\(ext)"
                previewMimeType = mime
                showPhotoPreview = true
                return // Превью только для первого
            } else {
                onPick(data, "photo.\(ext)", mime)
            }
        }
    }

    private func loadFile(_ url: URL) async {
        busy = true
        defer { busy = false }
        guard url.startAccessingSecurityScopedResource() else {
            error = "Нет доступа к файлу"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            error = "Не получилось прочитать файл"
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        onPick(data, url.lastPathComponent, mime)
    }
}

/// Превью фото перед отправкой
struct PhotoPreviewSheet: View {
    let image: UIImage
    let onSend: () -> Void
    let onCancel: () -> Void
    @State private var caption = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }

                VStack(spacing: 12) {
                    TextField("Добавить подпись...", text: $caption, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(1...5)

                    HStack(spacing: 12) {
                        Button("Отмена") {
                            onCancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Отправить") {
                            onSend()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Отправить фото")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
