import SwiftUI
import MapKit

/// Модальное окно для отправки геолокации
struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chatId: Int64
    @EnvironmentObject var client: MaxClient

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173), // Москва по умолчанию
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var sending = false
    @State private var error: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MapReader — правильный способ превратить тап в координаты:
                // его closure даёт MapProxy, у которого есть convert(_:from:).
                MapReader { proxy in
                    Map {
                        if let loc = selectedLocation {
                            Marker("Выбранное место", coordinate: loc)
                                .tint(.red)
                        }
                    }
                    .onTapGesture { location in
                        guard let coord = proxy.convert(location, from: .local) else { return }
                        selectedLocation = coord
                        region.center = coord
                    }
                }
                .frame(height: 400)
                .onAppear { region.center = selectedLocation ?? region.center }

                VStack(spacing: 16) {
                    if let loc = selectedLocation {
                        Text("📍 \(String(format: "%.4f, %.4f", loc.latitude, loc.longitude))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)

                        if !address.isEmpty {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Нажмите на карту, чтобы выбрать место")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Отправить геолокацию") {
                        Task { await sendLocation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLocation == nil || sending)

                    Button("Моё местоположение") {
                        Task { await useCurrentLocation() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(sending)
                }
                .padding()
            }
            .navigationTitle("Геолокация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("ОК") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func useCurrentLocation() async {
        // Здесь нужен CLLocationManager + NSLocationWhenInUseUsageDescription в
        // Info.plist. Пока не подключено — честно сообщаем, а не ставим заглушку
        // «Красная площадь», которая вводит в заблуждение.
        error = "Текущее местоположение пока не подключено."
    }

    private func sendLocation() async {
        guard let loc = selectedLocation else { return }
        sending = true
        defer { sending = false }

        do {
            try await client.sendLocation(
                chatId: chatId,
                latitude: loc.latitude,
                longitude: loc.longitude,
                address: address.isEmpty ? nil : address
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    struct MapPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }
}

/// Модальное окно для создания опроса
struct CreatePollSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chatId: Int64
    @EnvironmentObject var client: MaxClient

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var allowMultiple = false
    @State private var sending = false
    @State private var error: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Вопрос", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Вопрос")
                }

                Section {
                    ForEach(options.indices, id: \.self) { index in
                        HStack {
                            TextField("Вариант \(index + 1)", text: $options[index])
                            if options.count > 2 {
                                Button {
                                    options.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    if options.count < 10 {
                        Button {
                            options.append("")
                        } label: {
                            Label("Добавить вариант", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("Варианты ответов")
                }

                Section {
                    Toggle("Множественный выбор", isOn: $allowMultiple)
                }
            }
            .navigationTitle("Создать опрос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task { await createPoll() }
                    }
                    .disabled(!canCreate || sending)
                }
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("ОК") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var canCreate: Bool {
        !question.isEmpty && options.filter { !$0.isEmpty }.count >= 2
    }

    private func createPoll() async {
        sending = true
        defer { sending = false }

        let validOptions = options.filter { !$0.isEmpty }

        do {
            try await client.createPoll(
                chatId: chatId,
                question: question,
                options: validOptions,
                allowMultiple: allowMultiple
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Модальное окно для создания группы
struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var client: MaxClient

    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var creating = false
    @State private var error: String?
    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название группы", text: $groupName)
                    TextField("Описание (необязательно)", text: $groupDescription, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Информация о группе")
                }
            }
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task { await createGroup() }
                    }
                    .disabled(groupName.isEmpty || creating)
                }
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("ОК") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func createGroup() async {
        creating = true
        defer { creating = false }

        do {
            try await client.createGroup(
                title: groupName,
                memberIds: [],
                description: groupDescription.isEmpty ? nil : groupDescription
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
