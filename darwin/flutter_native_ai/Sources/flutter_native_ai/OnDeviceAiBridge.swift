import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

#if canImport(FoundationModels)
  import FoundationModels
#endif

#if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private final class LocalAiSession {
    let modelSession: LanguageModelSession

    init(instructions: String) {
      modelSession = LanguageModelSession(instructions: instructions)
    }
  }
#endif

/// Apple platform implementation of the Pigeon host API for Foundation Models.
///
/// The bridge is compiled even when the active SDK does not include
/// FoundationModels. Runtime availability checks keep unsupported OS versions
/// and unavailable model states out of the Dart UI layer.
final class OnDeviceAiBridge: OnDeviceAiHostApi {
  // Host methods are nonisolated `async`, so they no longer all resume on the
  // platform thread. Session storage is locked to keep the serialization the
  // callback-based bridge got from the main thread for free.
  private let sessionsLock = NSLock()
  private var sessions: [String: Any] = [:]
  private let streamHandler = LocalAiGenerationStreamHandler()
  private let statusHandler = LocalAiStatusStreamHandler()

  /// Registers the event-channel stream handler used by streaming generation.
  func registerStreamHandler(with messenger: FlutterBinaryMessenger) {
    GenerationStreamStreamHandler.register(
      with: messenger,
      streamHandler: streamHandler
    )
    StatusStreamStreamHandler.register(
      with: messenger,
      streamHandler: statusHandler
    )
  }

  /// Returns the current Apple Foundation Models support and readiness state.
  func status() async throws -> LocalAiStatusMessage {
    currentStatus()
  }

  /// Refreshes Apple readiness. Foundation Models does not expose app-triggered downloads.
  func ensureReady(
    policy: LocalAiInitializationPolicyMessage
  ) async throws -> LocalAiStatusMessage {
    let status = currentStatus()
    statusHandler.emit(status)
    return status
  }

  /// Creates a native Foundation Models session.
  func createSession(instructions: String) async throws -> String {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          throw PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )
        }

        let session = UUID().uuidString
        storeSession(LocalAiSession(instructions: instructions), for: session)
        return session
      } else {
        throw PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )
      }
    #else
      throw PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )
    #endif
  }

  /// Releases the native Foundation Models session.
  func disposeSession(session: String) async throws {
    streamHandler.cancel(session: session)
    removeSession(session)
  }

  /// Generates a complete response for one prompt.
  func generateText(
    session: String,
    prompt: String,
    config: LocalAiGenerationConfigMessage
  ) async throws -> LocalAiGenerationResponseMessage {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          throw PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )
        }

        guard let localSession = storedSession(session) as? LocalAiSession else {
          throw PigeonError(
            code: "local-ai-session-not-found",
            message: "The local AI session has already been disposed or was not created.",
            details: nil
          )
        }

        let startTime = Date()
        let options = GenerationOptions(
          temperature: config.temperature,
          maximumResponseTokens: config.maxTokens.map(Int.init)
        )

        do {
          let response = try await localSession.modelSession.respond(to: prompt, options: options)
          return LocalAiGenerationResponseMessage(
            text: response.content,
            tokenCount: nil,
            durationMs: Date().timeIntervalSince(startTime) * 1000
          )
        } catch {
          throw PigeonError(
            code: "local-ai-generation-failed",
            message: error.localizedDescription,
            details: String(describing: error)
          )
        }
      } else {
        throw PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )
      }
    #else
      throw PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )
    #endif
  }

  /// Starts a streaming response and returns chunks through the event channel.
  func startStreamingText(
    session: String,
    prompt: String,
    config: LocalAiGenerationConfigMessage
  ) async throws {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          throw PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )
        }

        guard let localSession = storedSession(session) as? LocalAiSession else {
          throw PigeonError(
            code: "local-ai-session-not-found",
            message: "The local AI session has already been disposed or was not created.",
            details: nil
          )
        }

        streamHandler.start(
          session: session,
          prompt: prompt,
          localSession: localSession,
          config: config
        )
      } else {
        throw PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )
      }
    #else
      throw PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )
    #endif
  }

  /// Cancels the active streaming generation task.
  func cancelStreamingText(session: String) async throws {
    streamHandler.cancel(session: session)
  }

  private func storeSession(_ value: Any, for session: String) {
    sessionsLock.lock()
    defer { sessionsLock.unlock() }
    sessions[session] = value
  }

  private func storedSession(_ session: String) -> Any? {
    sessionsLock.lock()
    defer { sessionsLock.unlock() }
    return sessions[session]
  }

  private func removeSession(_ session: String) {
    sessionsLock.lock()
    defer { sessionsLock.unlock() }
    sessions.removeValue(forKey: session)
  }

  /// Maps Foundation Models availability into a stable Pigeon message.
  private func currentStatus() -> LocalAiStatusMessage {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return LocalAiStatusMessage(
            isSupported: true,
            isReady: true,
            canInitialize: false,
            isInitializing: false,
            reason: nil,
            platformStatus: "available"
          )
        case .unavailable(let reason):
          return LocalAiStatusMessage(
            isSupported: true,
            isReady: false,
            canInitialize: false,
            isInitializing: false,
            reason: "Apple Foundation Models is unavailable: \(reason)",
            platformStatus: String(describing: reason)
          )
        @unknown default:
          return LocalAiStatusMessage(
            isSupported: true,
            isReady: false,
            canInitialize: false,
            isInitializing: false,
            reason: "Apple Foundation Models availability is unknown.",
            platformStatus: "unknown"
          )
        }
      }
    #endif

    return LocalAiStatusMessage(
      isSupported: false,
      isReady: false,
      canInitialize: false,
      isInitializing: false,
      reason: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
      platformStatus: "unsupported-os"
    )
  }
}

private extension LocalAiStatusMessage {
  var isAvailable: Bool {
    isSupported && isReady
  }
}

/// Event-channel handler for model initialization status snapshots.
final class LocalAiStatusStreamHandler: StatusStreamStreamHandler {
  private var sink: PigeonEventSink<LocalAiStatusMessage>?

  override func onListen(
    withArguments arguments: Any?,
    sink: PigeonEventSink<LocalAiStatusMessage>
  ) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func emit(_ status: LocalAiStatusMessage) {
    if Thread.isMainThread {
      sink?.success(status)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.sink?.success(status)
      }
    }
  }
}

/// Event-channel handler for streaming generation.
///
/// Streaming chunks share a single event channel without a session identifier,
/// so only one streaming generation may be active at a time per plugin
/// instance. Tasks are tracked per session so cancellation can target the
/// originating session, but starting a new stream cancels any in-flight one.
final class LocalAiGenerationStreamHandler: GenerationStreamStreamHandler {
  private var sink: PigeonEventSink<LocalAiStreamChunkMessage>?

  #if canImport(FoundationModels)
    private let tasksLock = NSLock()
    // The id lets a finishing task clear only its own entry, never the entry
    // of a stream that replaced it.
    private var currentTasks: [String: (id: UUID, task: Task<Void, Never>)] = [:]
  #endif

  /// Stores the active event sink for later generation chunks.
  override func onListen(
    withArguments arguments: Any?,
    sink: PigeonEventSink<LocalAiStreamChunkMessage>
  ) {
    self.sink = sink
  }

  /// Cancels generation and clears the event sink when Dart stops listening.
  override func onCancel(withArguments arguments: Any?) {
    cancelAll()
    sink = nil
  }

  /// Cancels the active Foundation Models task for a session.
  func cancel(session: String) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        tasksLock.lock()
        let entry = currentTasks.removeValue(forKey: session)
        tasksLock.unlock()
        entry?.task.cancel()
      }
    #endif
  }

  /// Cancels every active Foundation Models streaming task.
  func cancelAll() {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        tasksLock.lock()
        let tasks = currentTasks.values.map(\.task)
        currentTasks.removeAll()
        tasksLock.unlock()
        tasks.forEach { $0.cancel() }
      }
    #endif
  }

  #if canImport(FoundationModels)
    /// Starts a new Foundation Models streaming task.
    @available(iOS 26.0, macOS 26.0, *)
    fileprivate func start(
      session: String,
      prompt: String,
      localSession: LocalAiSession,
      config: LocalAiGenerationConfigMessage
    ) {
      // Streaming chunks share a single event channel without a session id, so
      // only one generation may stream at a time per plugin instance. Cancel
      // any in-flight stream (for this or another session) before starting.
      // Replacement happens under one lock so concurrent starts cannot both
      // survive.
      let temperature = config.temperature
      let maximumResponseTokens = config.maxTokens.map(Int.init)

      let taskID = UUID()
      tasksLock.lock()
      let replacedTasks = currentTasks.values.map(\.task)
      currentTasks.removeAll()
      let task = Task.detached(priority: .userInitiated) { [weak self] in
        do {
          let options = GenerationOptions(
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
          )
          let stream = localSession.modelSession.streamResponse(to: prompt, options: options)
          var latestText = ""

          for try await snapshot in stream {
            if Task.isCancelled {
              return
            }

            // Bound to a `let` per iteration: passing the snapshot as an
            // argument keeps a mutable local out of concurrently-executing code.
            let snapshotText = snapshot.content
            latestText = snapshotText
            await self?.sendChunk(text: snapshotText, isDone: false)
          }

          let finalText = latestText
          await self?.sendChunk(text: finalText, isDone: true)
        } catch is CancellationError {
          await self?.sendChunk(text: "", isDone: true)
        } catch {
          await self?.sendError(error)
        }

        self?.clearTask(session: session, id: taskID)
      }
      currentTasks[session] = (id: taskID, task: task)
      tasksLock.unlock()
      replacedTasks.forEach { $0.cancel() }
    }

    /// Drops the finished task entry unless a newer stream already replaced it.
    fileprivate func clearTask(session: String, id: UUID) {
      tasksLock.lock()
      defer { tasksLock.unlock() }
      if currentTasks[session]?.id == id {
        currentTasks[session] = nil
      }
    }
  #endif

  /// Sends a text snapshot to Dart on the main actor.
  @MainActor
  private func sendChunk(text: String, isDone: Bool) {
    sink?.success(LocalAiStreamChunkMessage(
      text: text,
      isDone: isDone,
      errorCode: nil,
      errorMessage: nil
    ))
  }

  /// Encodes generation failures as a terminal stream chunk.
  @MainActor
  private func sendError(_ error: Error) {
    sink?.success(LocalAiStreamChunkMessage(
      text: "",
      isDone: true,
      errorCode: "local-ai-generation-failed",
      errorMessage: error.localizedDescription
    ))
  }
}
