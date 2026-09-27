import SwiftUI

struct StickerPicker: View {
    @ObservedObject private var store = StickerStore.shared
    @Environment(\.dismiss) private var dismiss
    var onPick: (Sticker) -> Void

    private let cols = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        NavigationStack {
            Group {
                if store.all.isEmpty {
                    ContentUnavailableView(
                        "Стикеров пока нет",
                        systemImage: "face.smiling",
                        description: Text("Каталог наборов MAX закрыт. Как только вам пришлют стикер, он появится здесь, и его можно будет отправлять.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(store.all) { st in
                                Button {
                                    onPick(st)
                                    dismiss()
                                } label: {
                                    AsyncImage(url: st.imageURL) { img in
                                        img.resizable().scaledToFit()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.secondarySystemBackground))
                                    }
                                    .frame(width: 76, height: 76)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Стикеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
