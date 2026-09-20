import SwiftUI

struct AssistantSettingsView: View {
  var showsTitle = true
  @EnvironmentObject private var store: WorkspaceStore
  @State private var appleAvailability = AppleAssistantAvailability.current()
  @State private var key = ""
  @State private var hasKey = false
  @State private var status: String?
  @State private var isError = false
  @State private var isTesting = false
  @State private var testTask: Task<Void, Never>?
  private let credentials = AssistantKeychain()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if showsTitle { Text("Assistant").font(.strukturSerif(27, weight: .semibold)) }
        Text("A quiet place to think, plan, and take the next step. Open it from any page with ⌘ J.")
          .font(.system(size: 13)).foregroundStyle(StrukturTheme.muted).lineSpacing(3)
        providerChoices
        if provider == .apple {
          appleSettings
        } else {
          PreferenceGroup(title: "Connect OpenAI", detail: "Bring your own API key. It stays in this Mac’s Keychain, outside workspace backups.") {
            Label(hasKey ? "API key saved" : "No API key connected",
              systemImage: hasKey ? "key.fill" : "key").font(.system(size: 12))
            SecureField(hasKey ? "Replace API key" : "API key", text: $key).strukturInput()
              .accessibilityLabel("OpenAI API key")
            HStack {
              Button(hasKey ? "Replace key" : "Save key") { saveKey() }
                .buttonStyle(StrukturButtonStyle(primary: true))
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
              if hasKey {
                Button("Remove key", role: .destructive) {
                  do { try credentials.remove(); hasKey = false; key = ""; status = "API key removed."; isError = false }
                  catch { show(error) }
                }.disabled(isTesting)
              }
              Spacer()
              Link("Get an API key ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.system(size: 11))
            }
          }
          PreferenceGroup(title: "Model", detail: "Use a model that supports the Responses API and structured outputs.") {
            TextField("Model ID", text: Binding(
              get: { (store.preferences.assistant ?? AssistantPreferences()).model },
              set: { value in store.updatePreferences { var settings = $0.assistant ?? AssistantPreferences(); settings.model = value; $0.assistant = settings } }
            )).strukturInput().accessibilityLabel("Assistant model").disabled(isTesting)
            HStack {
              Button("Use default") { store.updatePreferences { var settings = $0.assistant ?? AssistantPreferences(); settings.model = AssistantPreferences().model; $0.assistant = settings } }.disabled(isTesting)
              Spacer()
              if isTesting { ProgressView().controlSize(.small) }
              Button(isTesting ? "Checking…" : "Test connection") { testConnection() }.disabled(!hasKey || isTesting)
            }
          }
        }
        if let status {
          Label(status, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.system(size: 12)).foregroundStyle(isError ? StrukturTheme.destructive : StrukturTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(provider == .apple
          ? "Apple’s Foundation Models framework processes requests on this Mac. No API key is needed and no requests are sent to OpenAI. It is best for focused summaries and extraction; larger notes use a labeled excerpt. You review every proposed addition."
          : "Only requests you send use AI. You choose the context each time; schedule context excludes note bodies. Conversation history stays in memory until you start a new conversation or close the window. API response storage is turned off. OpenAI’s data policies still apply. API billing is separate from ChatGPT.")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted).lineSpacing(3)
        Text(provider == .apple
          ? "Availability depends on macOS 26 or later, compatible hardware, language/region, and Apple Intelligence being enabled with its model downloaded. Check model runs a short on-device test with no workspace content."
          : "Test connection sends a short test message with no workspace content and may incur API usage.")
          .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
      }.padding(24).buttonStyle(StrukturButtonStyle())
    }
    .onAppear { refreshAvailability() }
    .onChange(of: provider) { _, _ in
      testTask?.cancel(); isTesting = false; status = nil; key = ""
      refreshAvailability()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshAvailability()
    }
    .onDisappear { testTask?.cancel() }
  }

  private var provider: AssistantProvider { (store.preferences.assistant ?? AssistantPreferences()).provider }

  private var providerChoices: some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(AssistantProvider.allCases) { choice in
        Button {
          store.updatePreferences {
            var settings = $0.assistant ?? AssistantPreferences()
            settings.provider = choice
            $0.assistant = settings
          }
        } label: {
          HStack(spacing: 12) {
            Image(systemName: choice == .apple ? "apple.logo" : "cloud").frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
              Text(choice.title).font(.system(size: 13, weight: .medium))
              Text(choice == .apple ? "Default · Private, on-device · No API key" : "Optional · Uses your API key and sends context to OpenAI")
                .font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
            }
            Spacer()
            Image(systemName: provider == choice ? "checkmark.circle.fill" : "circle")
          }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(provider == choice ? StrukturTheme.mint : StrukturTheme.surface,
              in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StrukturTheme.hairline) }
        }.buttonStyle(.plain).accessibilityLabel("Use \(choice == .apple ? "Apple on-device" : "OpenAI")")
          .accessibilityAddTraits(provider == choice ? .isSelected : [])
          .disabled(isTesting)
      }
    }
  }

  private var appleSettings: some View {
    PreferenceGroup(title: appleAvailability.title, detail: appleAvailability.detail) {
      HStack {
        Button("Refresh availability") { refreshAvailability() }.disabled(isTesting)
        Spacer()
        if isTesting { ProgressView().controlSize(.small) }
        Button(isTesting ? "Checking…" : "Check model") { testApple() }
          .buttonStyle(StrukturButtonStyle(primary: true)).disabled(!appleAvailability.isAvailable || isTesting)
      }
    }
  }

  private func refreshAvailability() {
    appleAvailability = .current()
    if provider == .openAI {
      do { hasKey = try credentials.read()?.isEmpty == false }
      catch { show(error) }
    }
  }

  private func testApple() {
    isTesting = true; status = nil
    testTask = Task { @MainActor in
      defer { isTesting = false }
      do {
        _ = try await AppleAssistantClient().respond(prompt: "Say hello in one short sentence. Do not create anything.",
          context: AssistantContext(json: "{}", summary: "Model check", projectIDs: []), history: [], model: "", apiKey: "")
        try Task.checkCancellation()
        status = "Ready. Apple’s model responded on this Mac."; isError = false
      } catch { if !Task.isCancelled { show(error) } }
    }
  }

  private func saveKey() {
    do {
      try credentials.save(key)
      key = ""; hasKey = true; status = "API key saved. Test the connection when you’re ready."; isError = false
    } catch { show(error) }
  }

  private func show(_ error: Error) { status = error.localizedDescription; isError = true }

  private func testConnection() {
    isTesting = true; status = nil
    testTask = Task { @MainActor in
      defer { isTesting = false }
      do {
        guard let key = try credentials.read() else { throw AssistantFailure("Save an API key first.") }
        _ = try await OpenAIAssistantClient().respond(prompt: "Reply with a short greeting and no actions.",
          context: AssistantContext(json: "{}", summary: "Connection test", projectIDs: []), history: [],
          model: (store.preferences.assistant ?? AssistantPreferences()).model, apiKey: key)
        try Task.checkCancellation()
        status = "Connected. Your model is ready."; isError = false
      } catch {
        if !Task.isCancelled { show(error) }
      }
    }
  }
}
