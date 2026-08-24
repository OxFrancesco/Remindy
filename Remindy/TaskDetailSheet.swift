import SwiftData
import SwiftUI

struct TaskDetailSheet: View {
    enum Mode {
        case create
        case edit(Reminder)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanner = NFCTagScanner()

    @State private var title: String
    @State private var note: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var recurrence: Recurrence
    @State private var isLogger: Bool
    @State private var linkedTagID: String?
    @State private var tagError: String?
    @State private var hasPlace: Bool
    @State private var placeName: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var radius: Double
    @State private var placeTrigger: PlaceTrigger
    @State private var showingPlacePicker = false
    @State private var newSubtaskTitle = ""
    @State private var nfcPulse = 0
    @FocusState private var titleFocused: Bool
    @FocusState private var subtaskFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        if case let .edit(task) = mode {
            _title = State(initialValue: task.title)
            _note = State(initialValue: task.note)
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? .now)
            _recurrence = State(initialValue: task.recurrence)
            _isLogger = State(initialValue: task.isLogger)
            _linkedTagID = State(initialValue: task.tagID)
            _hasPlace = State(initialValue: task.hasPlace)
            _placeName = State(initialValue: task.placeName)
            _latitude = State(initialValue: task.latitude)
            _longitude = State(initialValue: task.longitude)
            _radius = State(initialValue: max(50, task.radiusMeters))
            _placeTrigger = State(initialValue: task.placeTrigger)
        } else {
            _title = State(initialValue: "")
            _note = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: .now)
            _recurrence = State(initialValue: .none)
            _isLogger = State(initialValue: false)
            _linkedTagID = State(initialValue: nil)
            _hasPlace = State(initialValue: false)
            _placeName = State(initialValue: "")
            _latitude = State(initialValue: nil)
            _longitude = State(initialValue: nil)
            _radius = State(initialValue: 150)
            _placeTrigger = State(initialValue: .onEntry)
        }
    }

    private var existingTask: Reminder? {
        if case let .edit(task) = mode { return task }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                    TextField("Notes", text: $note)
                }

                Section {
                    Toggle("Auto-Reset After Log", isOn: $isLogger.animation(Motion.reveal))
                    if isLogger {
                        Text("Each tap logs the result and clears instantly \u{2014} ideal for things like locking the door.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Due Date", isOn: $hasDueDate.animation(Motion.reveal))
                        if hasDueDate {
                            DatePicker("Remind Me", selection: $dueDate)
                                .datePickerStyle(.graphical)
                                .transition(calendarTransition)
                        }
                        Picker("Repeats", selection: $recurrence) {
                            ForEach(Recurrence.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Details")
                }

                if !isLogger {
                    placeSection
                }

                if let task = existingTask {
                    subtasksSection(task)
                }

                nfcSection

                if let task = existingTask {
                    dangerSection(task)
                }
            }
            .navigationTitle(existingTask == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let task = existingTask {
                        Button("Done") {
                            persistEdits(to: task)
                            dismiss()
                        }
                    } else {
                        Button("Add") {
                            save()
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                guard existingTask == nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(0.55))
                    titleFocused = true
                }
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.6), trigger: nfcPulse)
            .sheet(isPresented: $showingPlacePicker) {
                placePicker
            }
        }
    }

    private var placeSection: some View {
        Section {
            Toggle("Remind Me at a Place", isOn: $hasPlace.animation(Motion.reveal))
            if hasPlace {
                Button {
                    showingPlacePicker = true
                } label: {
                    HStack {
                        Label(
                            latitude != nil && longitude != nil
                                ? (placeName.isEmpty ? "Selected place" : placeName)
                                : "Choose Location\u{2026}",
                            systemImage: "mappin.and.ellipse"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(latitude != nil ? Color.primary : Color.accentColor)
                        Spacer()
                        if latitude == nil {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if latitude != nil && longitude != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Radius") {
                            Text("\(Int(radius)) m")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $radius, in: 50...500, step: 25) {
                            Text("Radius")
                        }
                    }
                    Picker("Alert", selection: $placeTrigger) {
                        ForEach(PlaceTrigger.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } header: {
            Text("Place")
        } footer: {
            Text(hasPlace
                ? "You'll get an alarm when you \(placeTrigger == .onEntry ? "arrive at" : "leave") this place \u{2014} even if Remindy is closed."
                : "Get an alarm when you arrive at or leave a location.")
        }
    }

    private var placePicker: some View {
        PlacePickerSheet(
            initial: latitude != nil && longitude != nil
                ? PlaceSelection(latitude: latitude ?? 0, longitude: longitude ?? 0, name: placeName)
                : nil,
            onConfirm: { selection in
                latitude = selection.latitude
                longitude = selection.longitude
                placeName = selection.name
                LocationReminderStore.shared.requestPermissions()
            }
        )
    }

    private var calendarTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func subtasksSection(_ parent: Reminder) -> some View {
        Section("Subtasks") {
            ForEach(parent.subtasks) { subtask in
                SubtaskRow(subtask: subtask)
            }
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(parent.subtasks[index])
                }
            }
            TextField("Add Subtask", text: $newSubtaskTitle)
                .focused($subtaskFocused)
                .submitLabel(.done)
                .onSubmit {
                    addSubtask(to: parent)
                }
        }
    }

    private var nfcSection: some View {
        Section {
            if let id = linkedTagID {
                Label {
                    Text("Tag \(id.prefix(6))\u{2026}")
                } icon: {
                    Image(systemName: Symbols.nfc)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: linkedTagID)
                }
                .font(.callout.monospacedDigit())
                Button {
                    scanTag()
                } label: {
                    Label("Relink a Different Tag", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    linkedTagID = nil
                    tagError = nil
                } label: {
                    Text("Unlink")
                }
            } else {
                Button {
                    scanTag()
                } label: {
                    Label {
                        Text("Link NFC Tag")
                    } icon: {
                        Image(systemName: Symbols.nfc)
                            .symbolRenderingMode(.hierarchical)
                            .symbolEffect(.bounce, value: nfcPulse)
                            .symbolEffect(
                                .variableColor.iterative.reversing,
                                isActive: scanner.isScanning && !reduceMotion
                            )
                    }
                }
            }
            if let tagError {
                Label(tagError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("NFC Tag")
        } footer: {
            Text("Writes a Remindy link onto the tag. Tapping your iPhone on it completes this task \u{2014} even from the lock screen.")
        }
    }

    private func dangerSection(_ task: Reminder) -> some View {
        Section {
            Button {
                task.isArchived.toggle()
                LocationReminderStore.shared.reconcileNow()
                Haptics.success()
                dismiss()
            } label: {
                Label(
                    task.isArchived ? "Unarchive" : "Archive",
                    systemImage: "archivebox"
                )
            }
            Button(role: .destructive) {
                modelContext.delete(task)
                LocationReminderStore.shared.reconcileNow()
                dismiss()
            } label: {
                Label("Delete Reminder", systemImage: "trash")
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Reminder(
            title: trimmed,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: hasDueDate && !isLogger ? dueDate : nil,
            recurrence: isLogger ? .none : recurrence,
            isLogger: isLogger
        )
        task.tagID = linkedTagID
        applyPlace(to: task)
        modelContext.insert(task)
        LocationReminderStore.shared.reconcileNow()
        Haptics.success()
        dismiss()
    }

    private func persistEdits(to task: Reminder) {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? task.title : title
        task.note = note
        task.isLogger = isLogger
        if isLogger {
            task.dueDate = nil
            task.recurrence = .none
            task.clearPlace()
        } else {
            task.dueDate = hasDueDate ? dueDate : nil
            task.recurrence = recurrence
            applyPlace(to: task)
        }
        task.tagID = linkedTagID
        LocationReminderStore.shared.reconcileNow()
    }

    private func applyPlace(to task: Reminder) {
        if hasPlace, let latitude, let longitude {
            task.latitude = latitude
            task.longitude = longitude
            task.radiusMeters = radius
            task.placeName = placeName
            task.placeTrigger = placeTrigger
            task.ensureRegionID()
        } else {
            task.clearPlace()
        }
    }

    private func addSubtask(to parent: Reminder) {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subtask = Reminder(title: trimmed)
        modelContext.insert(subtask)
        parent.subtasks.append(subtask)
        newSubtaskTitle = ""
        subtaskFocused = true
    }

    private func scanTag() {
        nfcPulse += 1
        guard NFCTagScanner.isAvailable else {
            tagError = "NFC requires a physical iPhone."
            return
        }
        tagError = nil
        scanner.scan(mode: .write) { outcome in
            if let uid = outcome.uid {
                linkedTagID = uid
                tagError = outcome.error
                Haptics.success()
            } else if let error = outcome.error {
                tagError = error
                Haptics.error()
            }
        }
    }
}

private struct SubtaskRow: View {
    @Bindable var subtask: Reminder

    var body: some View {
        HStack(spacing: 12) {
            Button {
                subtask.toggleComplete()
                if subtask.isCurrentlyDone {
                    Haptics.success()
                }
            } label: {
                Image(systemName: subtask.isCurrentlyDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCurrentlyDone ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: subtask.isCurrentlyDone)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)

            TextField("Subtask", text: $subtask.title)
                .strikethrough(subtask.isCurrentlyDone)
                .foregroundStyle(subtask.isCurrentlyDone ? Color.secondary : Color.primary)
        }
    }
}
