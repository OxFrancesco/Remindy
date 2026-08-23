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
        } else {
            _title = State(initialValue: "")
            _note = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: .now)
            _recurrence = State(initialValue: .none)
            _isLogger = State(initialValue: false)
            _linkedTagID = State(initialValue: nil)
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
                if existingTask == nil {
                    titleFocused = true
                }
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.6), trigger: nfcPulse)
        }
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
        modelContext.insert(task)
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
        } else {
            task.dueDate = hasDueDate ? dueDate : nil
            task.recurrence = recurrence
        }
        task.tagID = linkedTagID
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
