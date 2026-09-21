import SwiftUI

struct AssistantPanel: View {
  @EnvironmentObject private var store: WorkspaceStore
  @ObservedObject var session: AssistantSession
  let anchor: Date
  let close: () -> Void
  @State private var showingSettings = false
  @State private var showingContext = false
  @State private var editing: AssistantAction?
  @State private var composerFocused = false

  private var selected: [AssistantAction] { session.proposals.filter { session.selectedIDs.contains($0.id) } }
  private var conflictCount: Int { selected.filter { !store.assistantConflicts($0, among: selected).isEmpty }.count }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(StrukturTheme.hairline)
      if session.isReady {
        transcript
        if !session.proposals.isEmpty { reviewFooter }
        composer
      } else {
        setup
      }
    }
    .background(StrukturTheme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(StrukturTheme.hairline) }
    .shadow(color: .black.opacity(0.12), radius: 20, x: -4, y: 8)
    .foregroundStyle(StrukturTheme.ink)
    .onAppear {
      refreshConnection()
      composerFocused = true
    }
    .onChange(of: store.preferences.assistant?.provider) { _, _ in refreshConnection() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshConnection()
    }
    .onChange(of: store.workspaceGeneration) { _, _ in session.reset() }
    .onExitCommand { if session.isWorking { session.stop() } else { close() } }
    .sheet(isPresented: $showingSettings, onDismiss: { refreshConnection(); composerFocused = true }) {
      VStack(spacing: 0) {
        AssistantSettingsView()
        Divider()
        HStack { Spacer(); Button("Done") { showingSettings = false }.keyboardShortcut(.cancelAction) }
          .padding(16).buttonStyle(StrukturButtonStyle())
      }.frame(width: 580, height: 610).background(StrukturTheme.canvas)
    }
    .sheet(item: $editing) { action in
      AssistantActionEditor(action: action) { updated in
        if let index = session.proposals.firstIndex(where: { $0.id == updated.id }) {
          session.proposals[index] = updated
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "suit.diamond.fill").font(.system(size: 14)).foregroundStyle(StrukturTheme.muted)
      Text("Assistant").font(.strukturSerif(20, weight: .medium))
      Spacer()
      contextInfo
      Button { session.reset(); composerFocused = true } label: { Image(systemName: "square.and.pencil") }
        .help("New conversation").accessibilityLabel("New conversation")
      Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
        .help("Assistant settings").accessibilityLabel("Assistant settings")
        .disabled(session.isPreview)
      Button(action: close) { Image(systemName: "xmark") }
        .help("Close assistant · ⌘ J").accessibilityLabel("Close assistant")
        .keyboardShortcut(.cancelAction)
    }
    .buttonStyle(.plain).font(.system(size: 13)).padding(18)
  }

  private var contextInfo: some View {
    Button { showingContext = true } label: { Image(systemName: "info.circle") }
      .buttonStyle(.plain).help("What the assistant sees").accessibilityLabel("Inspect shared context")
      .popover(isPresented: $showingContext) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Relevant context, automatically").font(.strukturSerif(19))
          Text(session.provider == .apple
            ? "The assistant selects relevant tasks, calendar blocks, space names, or note excerpts on this Mac. Recent conversation excerpts help with follow-ups."
            : "When you send, the assistant can look up relevant tasks, calendar blocks, space names, or note excerpts. Your message, bounded recent conversation, and retrieved context are sent to OpenAI.")
            .font(.caption).foregroundStyle(StrukturTheme.muted)
          ScrollView {
            Text(session.lastContext ?? "No workspace content has been requested yet.")
              .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Text("Last request shown above. Note images and task/event note bodies are excluded. Changing provider starts a new conversation.")
            .font(.caption2).foregroundStyle(StrukturTheme.muted)
        }.padding(20).frame(width: 400, height: 420)
      }
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if session.turns.isEmpty { welcome }
          ForEach(session.turns) { turn in
            VStack(alignment: .leading, spacing: 6) {
              Text(turn.role == "user" ? "YOU" : "STRUKTUR")
                .font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(StrukturTheme.muted)
              // Render as text: a generated URL must not initiate an external action.
              Text(turn.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(turn.role == "user" ? 12 : 0)
            .background(turn.role == "user" ? StrukturTheme.canvas : .clear,
              in: RoundedRectangle(cornerRadius: 12))
          }
          if session.isWorking {
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text("Thinking it through…").font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
              Spacer()
              Button("Stop") { session.stop() }.buttonStyle(.plain)
            }.accessibilityElement(children: .contain)
          }
          if !session.proposals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Text("REVIEW & ADD").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(StrukturTheme.muted)
              ForEach(session.proposals) { action in actionCard(action) }
            }.disabled(session.isWorking)
          }
          if let outcome = session.outcome {
            VStack(alignment: .leading, spacing: 8) {
              Label(outcome, systemImage: "checkmark.circle").font(.system(size: 12))
              if session.receipt != nil {
                Button("Undo addition") { session.undo(store: store) }
                  .buttonStyle(StrukturButtonStyle(compact: true)).disabled(session.isWorking)
              }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
              .background(StrukturTheme.mint, in: RoundedRectangle(cornerRadius: 12))
          }
          if let error = session.error {
            Label(error, systemImage: "exclamationmark.circle")
              .font(.system(size: 12)).foregroundStyle(StrukturTheme.destructive)
              .fixedSize(horizontal: false, vertical: true)
          }
          Color.clear.frame(height: 1).id("latest")
        }.padding(18)
      }
      .onChange(of: session.turns.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
      .onChange(of: session.isWorking) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
      .onChange(of: session.outcome) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
      .onChange(of: session.error) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
    }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("A little clarity.\nA next step.").font(.strukturSerif(28)).lineSpacing(2)
      Text("Make sense of your day, untangle a note, or turn an idea into something you can do.")
        .font(.system(size: 13)).foregroundStyle(StrukturTheme.muted).lineSpacing(3)
      VStack(spacing: 8) {
        suggestion("Give me a day brief", icon: "sun.max", prompt: "Summarize my selected day, deadlines, and open tasks. What deserves my attention?")
        suggestion("Turn a note into next steps", icon: "checklist", prompt: "Suggest tasks from this note. Keep explicit deadlines, and ask if anything is ambiguous.")
        suggestion("Make room for focused work", icon: "calendar", prompt: "Help me plan a focus block. Ask me which task, day, and duration I have in mind.")
      }
      Text("You review every proposed item before it is added.")
        .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
    }.padding(.vertical, 12)
  }

  private func suggestion(_ title: String, icon: String, prompt: String) -> some View {
    Button {
      session.draft = prompt
      composerFocused = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: icon).frame(width: 16).foregroundStyle(StrukturTheme.muted)
        Text(title).font(.system(size: 12))
        Spacer()
        Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
      }.padding(12).background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain)
  }

  private func actionCard(_ action: AssistantAction) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        Toggle(isOn: Binding(get: { session.selectedIDs.contains(action.id) }, set: { value in
          if value { session.selectedIDs.insert(action.id) } else { session.selectedIDs.remove(action.id) }
        })) { Text(action.title).font(.system(size: 13, weight: .medium)) }
          .toggleStyle(.checkbox).accessibilityLabel("Include \(action.title)")
        Spacer(minLength: 0)
        Button("Edit") { editing = action }.buttonStyle(.plain).font(.system(size: 11))
          .accessibilityLabel("Edit \(action.title)")
      }
      Label(action.kind == .task ? "Task" : "Calendar block · \(action.eventKind.title)",
        systemImage: action.kind == .task ? "checkmark.circle" : "calendar")
        .font(.system(size: 10, weight: .medium)).foregroundStyle(StrukturTheme.muted)
      if action.kind == .task, action.priority != .normal {
        Text("\(action.priority.title) priority").font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
      }
      if let due = action.dueDate {
        Label("Due \(due.formatted(date: .abbreviated, time: .shortened))", systemImage: "flag")
          .font(.system(size: 11))
      }
      if let span = action.interval {
        Label("\(span.start.formatted(date: .abbreviated, time: .shortened)) → \(span.end.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
          .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
      } else if action.kind == .task {
        Text(action.estimateMinutes.map { "Unscheduled · \($0) min estimate" } ?? "Unscheduled · No duration estimate")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
      }
      if let project = store.project(action.projectID) {
        Label(project.name, systemImage: project.symbol.icon).font(.system(size: 11))
      }
      if !action.location.isEmpty {
        Label(action.location, systemImage: "mappin").font(.system(size: 11))
      }
      if !action.notes.isEmpty {
        Text(action.notes).font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      let conflicts = store.assistantConflicts(action, among: selected)
      if !conflicts.isEmpty, session.selectedIDs.contains(action.id) {
        Label("Overlaps: \(conflicts.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.destructive)
          .fixedSize(horizontal: false, vertical: true)
      }
    }.padding(12).background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StrukturTheme.hairline) }
  }

  private var reviewFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
      if conflictCount > 0 {
        Text("\(conflictCount) selected \(conflictCount == 1 ? "item overlaps" : "items overlap") existing or proposed work. Edit the times or add with overlaps.")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.destructive)
      }
      HStack {
        Text("\(selected.count) selected").font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
        Spacer()
        Button(conflictCount > 0 ? "Add with overlaps" : "Add to workspace") { session.apply(store: store) }
          .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
          .disabled(selected.isEmpty || session.isWorking)
      }
    }.padding(14).background(StrukturTheme.canvas)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      AssistantComposer(text: $session.draft, focused: $composerFocused, isEnabled: !session.isWorking) {
        if canSend { session.send(store: store, anchor: anchor) }
      }.frame(height: 58)
        .overlay(alignment: .topLeading) {
          if session.draft.isEmpty {
            Text("Ask, plan, or capture an idea…").font(.system(size: 13))
              .foregroundStyle(StrukturTheme.muted).padding(.top, 4).allowsHitTesting(false)
          }
        }
      HStack {
        Text(session.isPreview ? "Simulated preview · ↩ Send · ⇧↩ New line" : (session.provider == .apple ? "On this Mac · ↩ Send · ⇧↩ New line" : "OpenAI · ↩ Send · ⇧↩ New line"))
          .font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
        Spacer()
        Button { session.send(store: store, anchor: anchor) } label: {
          Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)).frame(width: 18, height: 18)
        }
        .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
        .accessibilityLabel("Send to assistant").help("Send · Return")
        .disabled(!canSend)
      }
      if session.draft.count > session.provider.messageLimit {
        Text("Message is too long (\(session.provider.messageLimit) characters maximum).")
          .font(.caption).foregroundStyle(StrukturTheme.destructive)
      }
    }.padding(16).background(StrukturTheme.surface)
      .overlay(alignment: .top) { Divider() }
  }

  private var setup: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("A thoughtful hand,\nwhenever you need it.").font(.strukturSerif(28)).lineSpacing(3)
      Text("Summarize your day and notes. Turn plans into tasks and calendar blocks, right here in Struktur.")
        .font(.system(size: 13)).lineSpacing(4).foregroundStyle(StrukturTheme.muted)
      Label("Open anytime with ⌘ J", systemImage: "keyboard")
      Label("Finds relevant context automatically", systemImage: "sparkles")
      Label("Review, edit, and undo additions", systemImage: "checkmark.circle")
      if session.provider == .apple {
        VStack(alignment: .leading, spacing: 8) {
          Label(session.appleAvailability.title, systemImage: "apple.logo").font(.system(size: 12, weight: .medium))
          Text(session.appleAvailability.detail).font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
        }.padding(14).background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
        HStack {
          Button("Check again") { refreshConnection() }
          Button("Assistant settings") { showingSettings = true }
        }.buttonStyle(StrukturButtonStyle())
        Text("Apple runs on-device. OpenAI is optional and is used only when you select it in settings.")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
      } else {
        Button("Connect OpenAI") { showingSettings = true }.buttonStyle(StrukturButtonStyle(primary: true))
        Text("Uses your own API key. API billing is separate from ChatGPT. Or select Apple in settings to work on-device.")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted).lineSpacing(3)
      }
      if let error = session.error { Text(error).font(.caption).foregroundStyle(StrukturTheme.destructive) }
      Spacer()
    }.font(.system(size: 12)).padding(24).padding(.top, 14).frame(maxHeight: .infinity, alignment: .top)
  }

  private var canSend: Bool {
    session.isReady && !session.isWorking && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && session.draft.count <= session.provider.messageLimit
  }
  private func refreshConnection() {
    session.refreshConnection(preferences: store.preferences.assistant ?? AssistantPreferences())
  }
}

struct AssistantActionEditor: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State var action: AssistantAction
  let save: (AssistantAction) -> Void
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(title: "Review \(action.kind == .task ? "task" : "calendar block")",
        subtitle: "Adjust this draft before adding it to your workspace.")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TextField("Title", text: $action.title).font(.strukturSerif(24)).textFieldStyle(.plain)
          StrukturMenuPicker(title: "Space", selection: $action.projectID,
            options: [StrukturMenuOption(value: UUID?.none, title: "None")] + store.projects.map {
              StrukturMenuOption(value: Optional($0.id), title: $0.name)
            })
          if action.kind == .task {
            Toggle("Has a deadline", isOn: Binding(get: { action.dueDate != nil }, set: {
              action.dueDate = $0 ? Date().setting(hour: 17) : nil
            }))
            if action.dueDate != nil {
              StrukturDateField("Deadline", selection: Binding(get: { action.dueDate ?? Date() }, set: { action.dueDate = $0 }))
            }
            Toggle("Schedule time", isOn: Binding(get: { action.start != nil }, set: {
              action.start = $0 ? Date().addingTimeInterval(3600) : nil
              if $0 { action.estimateMinutes = action.estimateMinutes ?? 30 }
            }))
            if action.start != nil {
              StrukturDateField("Scheduled start", selection: Binding(get: { action.start ?? Date() }, set: { action.start = $0 }))
            }
            Toggle("Estimate duration", isOn: Binding(get: { action.estimateMinutes != nil }, set: {
              action.estimateMinutes = $0 ? (action.estimateMinutes ?? 30) : nil
            })).disabled(action.start != nil)
            HStack {
              if action.estimateMinutes != nil {
                StrukturValueStepper(title: "Estimated duration",
                  value: Binding(get: { action.estimateMinutes ?? 30 }, set: { action.estimateMinutes = $0 }),
                  range: 1...1440, valueText: { "\($0) min" })
              }
              StrukturMenuPicker(title: "Priority", selection: $action.priority,
                options: TaskPriority.allCases.map { StrukturMenuOption(value: $0, title: $0.title) })
            }
          } else {
            StrukturDateField("Starts", selection: Binding(get: { action.start ?? Date() }, set: { action.start = $0 }))
            StrukturDateField("Ends", selection: Binding(get: { action.end ?? Date() }, set: { action.end = $0 }), minimumDate: action.start)
            StrukturMenuPicker(title: "Label", selection: $action.eventKind,
              options: ItemKind.allCases.map { StrukturMenuOption(value: $0, title: $0.title) })
            TextField("Location", text: $action.location).strukturInput()
          }
          TextField("Notes", text: $action.notes, axis: .vertical).lineLimit(3...8).strukturInput()
          if let error { Text(error).font(.caption).foregroundStyle(StrukturTheme.destructive) }
        }.padding(24)
      }
      Divider()
      HStack {
        Text("Times use \(Calendar.struktur.timeZone.identifier)").font(.caption2).foregroundStyle(StrukturTheme.muted)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Keep changes") {
          do {
            try action.validate(projectIDs: Set(store.projects.map(\.id)))
            save(action); dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(StrukturButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
      }.buttonStyle(StrukturButtonStyle()).padding(16)
    }.frame(width: 580, height: 620).background(StrukturTheme.canvas)
  }
}
