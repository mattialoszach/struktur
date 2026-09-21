import Foundation
import Combine

@MainActor
final class AssistantSession: ObservableObject {
  @Published var draft = ""
  @Published private(set) var turns: [AssistantTurn] = []
  @Published var proposals: [AssistantAction] = []
  @Published var selectedIDs: Set<UUID> = []
  @Published private(set) var isWorking = false
  @Published private(set) var hasKey = false
  @Published private(set) var provider: AssistantProvider = .apple
  @Published private(set) var appleAvailability: AppleAssistantAvailability = .unknown
  @Published var error: String?
  @Published private(set) var receipt: AssistantReceipt?
  @Published private(set) var outcome: String?
  @Published private(set) var lastContext: String?
  private var history: [AssistantTurn] = []
  private var requestTask: Task<Void, Never>?
  private var requestID = UUID()
  private var generation: UUID?
  private let client: any AssistantServing
  private let appleClient: any AssistantServing
  private let checkAppleAvailability: @Sendable () -> AppleAssistantAvailability
  private let credentials: any AssistantCredentialStore
  let isPreview: Bool

  init(client: any AssistantServing = OpenAIAssistantClient(),
    credentials: any AssistantCredentialStore = AssistantKeychain(), isPreview: Bool = false,
    appleClient: any AssistantServing = AppleAssistantClient(),
    appleAvailability: @escaping @Sendable () -> AppleAssistantAvailability = { .current() }) {
    self.client = client
    self.appleClient = appleClient
    self.checkAppleAvailability = appleAvailability
    self.credentials = credentials
    self.isPreview = isPreview
  }

  static func forLaunch() -> AssistantSession {
    #if DEBUG
      if ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW"] == "1",
        ["assistant", "assistant-calendar", "assistant-tasks"].contains(ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW_FIXTURE"] ?? "") {
        return AssistantSession(client: PreviewAssistantClient(), credentials: PreviewAssistantCredentials(), isPreview: true)
      }
    #endif
    return AssistantSession()
  }

  var isReady: Bool { isPreview || (provider == .apple ? appleAvailability.isAvailable : hasKey) }

  func refreshConnection(preferences: AssistantPreferences = AssistantPreferences()) {
    if provider != preferences.provider {
      if isWorking { stop() }
      reset()
      provider = preferences.provider
    }
    if provider == .apple {
      appleAvailability = checkAppleAvailability()
      hasKey = false
    } else {
      do { hasKey = try credentials.read()?.isEmpty == false }
      catch { hasKey = false; self.error = error.localizedDescription }
    }
  }

  func cancel() {
    requestID = UUID()
    requestTask?.cancel()
    requestTask = nil
    isWorking = false
  }

  func reset() {
    cancel()
    turns = []; history = []; proposals = []; selectedIDs = []
    receipt = nil; outcome = nil; error = nil; lastContext = nil; generation = nil
  }

  func send(store: WorkspaceStore, anchor: Date) {
    guard !isWorking else { return }
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let preferences = store.preferences.assistant ?? AssistantPreferences()
    refreshConnection(preferences: preferences)
    guard !prompt.isEmpty, prompt.count <= provider.messageLimit else {
      error = "Keep your message between 1 and \(provider.messageLimit) characters."
      return
    }
    do {
      var key = ""
      let selectedClient: any AssistantServing
      if isPreview { selectedClient = client }
      else if provider == .apple {
        guard appleAvailability.isAvailable else {
          throw AssistantFailure(appleAvailability.title + ". " + appleAvailability.detail)
        }
        selectedClient = appleClient
      } else {
        guard let savedKey = try credentials.read(), !savedKey.isEmpty else {
          hasKey = false
          throw AssistantFailure("Connect an API key in Assistant settings to start.")
        }
        key = savedKey
        selectedClient = client
      }
      let context = try store.assistantOverview(anchor: anchor)
      if let generation, generation != store.workspaceGeneration { reset() }
      let workspaceGeneration = store.workspaceGeneration
      generation = workspaceGeneration
      let token = UUID()
      requestID = token
      let previous = history
      let model = preferences.model
      let requestProvider = provider
      error = nil; isWorking = true
      lastContext = context.json
      let userTurn = AssistantTurn(role: "user", text: prompt)
      turns.append(userTurn)
      draft = ""
      requestTask = Task { [weak self, selectedClient] in
        do {
          let retrieve: AssistantRetrieve = { [weak self] query in
            try Task.checkCancellation()
            guard let self, self.requestID == token,
              store.workspaceGeneration == workspaceGeneration,
              (store.preferences.assistant ?? AssistantPreferences()).provider == requestProvider else {
              throw CancellationError()
            }
            let found = try store.assistantContext(request: query, anchor: anchor, provider: requestProvider)
            self.lastContext = (self.lastContext ?? "") + "\n\n" + found.json
            return found
          }
          let reply: AssistantReply
          if AssistantTaskContext.isListing(prompt) {
            reply = try AssistantTaskContext.reply(retrieve(.init(tasks: true)))
          } else if let query = try AssistantCalendarQuery.resolve(prompt: prompt, history: previous, context: context) {
            let snapshot = try query.request.map { try retrieve($0) } ?? context
            reply = try query.reply(context: snapshot)
          } else {
            let responseContext = AssistantTaskContext.needsContext(prompt)
              ? try AssistantTaskContext.merging(retrieve(.init(tasks: true)), into: context, provider: requestProvider) : context
            reply = try await selectedClient.respond(prompt: prompt, context: responseContext, history: previous,
              model: model, apiKey: key, retrieve: retrieve)
          }
          try Task.checkCancellation()
          guard let self, self.requestID == token else { return }
          guard store.workspaceGeneration == workspaceGeneration else {
            self.reset()
            self.draft = prompt
            self.error = "The workspace changed while the assistant was working. Send your message again."
            return
          }
          guard (store.preferences.assistant ?? AssistantPreferences()).provider == requestProvider else {
            self.reset()
            self.draft = prompt
            self.refreshConnection(preferences: store.preferences.assistant ?? AssistantPreferences())
            return
          }
          self.turns.append(AssistantTurn(role: "assistant", text: reply.message))
          self.proposals = reply.actions
          self.selectedIDs = Set(reply.actions.map(\.id))
          self.receipt = nil; self.outcome = nil
          self.history = AssistantTurn.bounded(previous + [userTurn, AssistantTurn(role: "assistant",
            text: reply.message + Self.proposalDescription(reply.actions))])
          self.isWorking = false
          self.requestTask = nil
        } catch {
          guard let self, self.requestID == token else { return }
          self.turns.removeAll { $0.id == userTurn.id }
          if self.draft.isEmpty { self.draft = prompt }
          if !(error is CancellationError) { self.error = error.localizedDescription }
          self.isWorking = false
          self.requestTask = nil
        }
      }
    } catch { self.error = error.localizedDescription }
  }

  func stop() {
    if let last = turns.last, last.role == "user" {
      if draft.isEmpty { draft = last.text }
      turns.removeLast()
    }
    cancel()
    outcome = "Stopped. Your message is ready to try again."
  }

  func apply(store: WorkspaceStore) {
    guard !isWorking, receipt == nil, let generation else { return }
    do {
      let selected = proposals.filter { selectedIDs.contains($0.id) }
      receipt = try store.applyAssistantActions(selected, generation: generation)
      outcome = "Added \(selected.count) \(selected.count == 1 ? "item" : "items") to your workspace."
      history.append(AssistantTurn(role: "user", text: "APP RESULT: Added the following items. Do not recreate them.\(Self.proposalDescription(selected))"))
      proposals = []; selectedIDs = []; error = nil
    } catch { self.error = error.localizedDescription }
  }

  func undo(store: WorkspaceStore) {
    guard let receipt, !isWorking else { return }
    do {
      try store.undoAssistantActions(receipt)
      self.receipt = nil; outcome = "Undone. The added items were removed."
      history.append(AssistantTurn(role: "user", text: "APP RESULT: User undid the last creation batch."))
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func waitForResponse() async { await requestTask?.value }

  private static func proposalDescription(_ actions: [AssistantAction]) -> String {
    let formatter = ISO8601DateFormatter()
    return "\nAction details:\n" + actions.map { action in
      "\(action.kind.rawValue): \(action.title); notes: \(action.notes); space: \(action.projectID?.uuidString ?? "none"); deadline: \(action.dueDate.map(formatter.string) ?? "none"); start: \(action.start.map(formatter.string) ?? "none"); end: \(action.end.map(formatter.string) ?? "none"); estimated minutes: \(action.estimateMinutes.map(String.init) ?? "none")"
    }.joined(separator: "\n")
  }
}

#if DEBUG
private struct PreviewAssistantCredentials: AssistantCredentialStore {
  func read() throws -> String? { "preview-only" }
  func save(_ key: String) throws {}
  func remove() throws {}
}
private struct PreviewAssistantClient: AssistantServing {
  func respond(prompt: String, context: AssistantContext, history: [AssistantTurn],
    model: String, apiKey: String) async throws -> AssistantReply {
    try await Task.sleep(for: .milliseconds(600))
    if prompt.localizedCaseInsensitiveContains("summar") || prompt.localizedCaseInsensitiveContains("brief") {
      return AssistantReply(message: "This is a simulated preview answer. Your schedule and open tasks are available as context. Try asking to create a task and a calendar block to exercise the review flow.", actions: [])
    }
    let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400 + 10 * 3600)
    return AssistantReply(message: "Two draft items are ready to review. The task has a deadline; the calendar block reserves time with a clear end. This is a simulated preview response.", actions: [
      AssistantAction(kind: .task, title: "Review lecture notes", notes: "Collect the three key ideas.", dueDate: start.addingTimeInterval(7 * 3600)),
      AssistantAction(kind: .event, title: "Study session", start: start, end: start.addingTimeInterval(3600), eventKind: .deepWork),
    ])
  }
}
#endif
