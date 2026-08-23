import SwiftData
import SwiftUI
import TipKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Reminder.createdAt) private var tasks: [Reminder]

    @State private var scanner = NFCTagScanner()
    @State private var creatingTask = false
    @State private var editingTask: Reminder?
    @State private var showArchived = false
    @State private var showingHistory = false
    @State private var toast: ToastData?
    @State private var toastTask: Task<Void, Never>?
    @State private var unavailableAlert = false
    @State private var nfcPulse = 0
    @State private var calendarPulse = 0

    private let historyTip = HistoryCalendarTip()

    struct ToastData: Equatable {
        var icon: String
        var message: String
    }

    private struct Sections {
        var active: [Reminder] = []
        var completed: [Reminder] = []
        var archived: [Reminder] = []

        var isEmpty: Bool { active.isEmpty && completed.isEmpty && archived.isEmpty }
    }

    private func makeSections() -> Sections {
        var sections = Sections()
        for task in tasks where task.parent == nil {
            if task.isArchived {
                sections.archived.append(task)
            } else if task.isCurrentlyDone {
                sections.completed.append(task)
            } else {
                sections.active.append(task)
            }
        }
        sections.active.sort { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.createdAt < rhs.createdAt
            }
        }
        sections.completed.sort {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
        sections.archived.sort { $0.createdAt > $1.createdAt }
        return sections
    }

    var body: some View {
        let sections = makeSections()
        return NavigationStack {
            Group {
                if sections.isEmpty {
                    EmptyTasksView(onAdd: { creatingTask = true })
                } else {
                    list(sections)
                }
            }
            .navigationTitle("Remindy")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Read NFC", systemImage: Symbols.nfc, action: startScan)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: nfcPulse)
                        .symbolEffect(
                            .variableColor.iterative.reversing,
                            isActive: scanner.isScanning && !reduceMotion
                        )
                        .help("Hold your iPhone near a linked tag")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("History", systemImage: "calendar", action: openHistory)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: calendarPulse)
                        .help("Activity calendar")
                        .popoverTip(historyTip, arrowEdge: .top)
                        .tipViewStyle(HistoryTipStyle())

                    Menu {
                        Toggle(isOn: $showArchived) {
                            Label("Show Archived", systemImage: "archivebox")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }

                    Button("Add Reminder", systemImage: "plus") {
                        creatingTask = true
                    }
                    .help("New reminder")
                }
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $creatingTask) {
                TaskDetailSheet(mode: .create)
            }
            .sheet(item: $editingTask) { task in
                TaskDetailSheet(mode: .edit(task))
            }
            .onOpenURL { url in
                handleTagURL(url)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastBanner(icon: toast.icon, message: toast.message)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.toast, value: toast)
            .simultaneousGesture(
                DragGesture(minimumDistance: 45)
                    .onEnded { value in
                        guard !showingHistory,
                              value.translation.width < -80,
                              abs(value.translation.height) < 60
                        else { return }
                        openHistory()
                    }
            )
            .alert("NFC Unavailable", isPresented: $unavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("NFC requires a physical iPhone.")
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: nfcPulse)
            .sensoryFeedback(.selection, trigger: calendarPulse)
        }
    }

    private func list(_ sections: Sections) -> some View {
        List {
            ForEach(sections.active) { task in
                row(for: task)
            }
            .onDelete { offsets in
                deleteActive(at: offsets, in: sections)
            }

            if !sections.completed.isEmpty {
                Section("Completed") {
                    ForEach(sections.completed) { task in
                        row(for: task)
                    }
                }
            }

            if showArchived && !sections.archived.isEmpty {
                Section("Archived") {
                    ForEach(sections.archived) { task in
                        row(for: task)
                    }
                }
            }
        }
    }

    private func row(for task: Reminder) -> some View {
        TaskRow(
            task: task,
            onTap: { editingTask = task },
            onToggle: { toggleComplete(task) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                task.isArchived.toggle()
            } label: {
                Label(
                    task.isArchived ? "Unarchive" : "Archive",
                    systemImage: task.isArchived ? "arrow.up.bin" : "archivebox"
                )
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button {
                editingTask = task
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                toggleComplete(task)
            } label: {
                Label(
                    task.isCurrentlyDone ? "Mark Open" : "Complete",
                    systemImage: task.isCurrentlyDone ? "circle" : "checkmark.circle.fill"
                )
            }
            Button {
                task.isArchived.toggle()
            } label: {
                Label(task.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                modelContext.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func deleteActive(at offsets: IndexSet, in sections: Sections) {
        for index in offsets {
            modelContext.delete(sections.active[index])
        }
    }

    private func toggleComplete(_ task: Reminder) {
        task.toggleComplete()
        if task.isCurrentlyDone {
            Haptics.success()
        }
    }

    private func openHistory() {
        historyTip.invalidate(reason: .actionPerformed)
        calendarPulse += 1
        showingHistory = true
    }

    private func startScan() {
        nfcPulse += 1
        guard NFCTagScanner.isAvailable else {
            unavailableAlert = true
            return
        }
        scanner.scan(mode: .read) { outcome in
            if let error = outcome.error {
                showToast(icon: "exclamationmark.triangle.fill", error)
            } else if let uid = outcome.uid {
                completeByTag(uid)
            }
        }
    }

    private func handleTagURL(_ url: URL) {
        guard url.scheme == "remindy", url.host == "t",
              let uid = url.pathComponents.last, !uid.isEmpty else { return }
        completeByTag(uid)
    }

    private func completeByTag(_ uid: String) {
        guard let task = tasks.first(where: { $0.parent == nil && !$0.isArchived && $0.tagID == uid }) else {
            Haptics.warning()
            showToast(icon: "questionmark.circle.fill", "Unknown tag")
            return
        }
        if task.isCurrentlyDone {
            showToast(icon: "checkmark.circle.fill", "\u{201C}\(task.title)\u{201D} already done")
            return
        }
        task.complete()
        Haptics.success()
        if task.isLogger {
            showToast(icon: "text.badge.checkmark", "\u{201C}\(task.title)\u{201D} logged")
        } else if task.recurrence != .none {
            showToast(icon: "repeat", "\u{201C}\(task.title)\u{201D} done \u{2014} repeats \(task.recurrence.label.lowercased())")
        } else {
            showToast(icon: "checkmark.circle.fill", "\u{201C}\(task.title)\u{201D} completed")
        }
    }

    private func showToast(icon: String, _ message: String) {
        toastTask?.cancel()
        withAnimation(Motion.toast) {
            toast = ToastData(icon: icon, message: message)
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.toast) {
                toast = nil
            }
        }
    }
}

private struct EmptyTasksView: View {
    let onAdd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var live = false

    var body: some View {
        ContentUnavailableView {
            Label("Nothing to tick off", systemImage: Symbols.nfc)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.variableColor.iterative.reversing, isActive: live && !reduceMotion)
        } description: {
            Text("Add a reminder, link a tag, then tap your iPhone on it.")
        } actions: {
            Button("New Reminder", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .onAppear { live = true }
    }
}

private struct ToastBanner: View {
    let icon: String
    let message: String

    var body: some View {
        Label(message, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.bounce, value: message)
    }
}

private struct TaskRow: View {
    let task: Reminder
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCurrentlyDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCurrentlyDone ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: task.isCurrentlyDone)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isCurrentlyDone ? "Mark open" : "Complete")

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .strikethrough(task.isCurrentlyDone)
                        .foregroundStyle(task.isCurrentlyDone ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    metadata
                }
            }
            .buttonStyle(RowPressStyle())

            if task.tagID != nil {
                Image(systemName: Symbols.nfc)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .speed(0.8), value: task.tagID)
                    .accessibilityLabel("NFC linked")
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        let hasMetadata = task.dueDate != nil || task.recurrence != .none || task.subtaskProgress != nil || task.isLogger
        if hasMetadata {
            HStack(spacing: 6) {
                if let due = task.dueDate {
                    MetaChip(
                        icon: "calendar",
                        text: dueText(due),
                        tint: task.isOverdue ? .red : .secondary
                    )
                }
                if task.recurrence != .none {
                    MetaChip(icon: "repeat", text: task.recurrence.label)
                }
                if task.isLogger, let last = task.lastLogged {
                    MetaChip(icon: "text.badge.checkmark", text: lastLoggedText(last))
                }
                if let progress = task.subtaskProgress {
                    MetaChip(icon: "list.bullet", text: progress)
                }
            }
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func lastLoggedText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Logged \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) { return "Logged yesterday" }
        return "Logged \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct MetaChip: View {
    let icon: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    ContentView()
}
