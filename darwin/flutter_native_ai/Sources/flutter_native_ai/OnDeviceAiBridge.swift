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
  func status(completion: @escaping (Result<LocalAiStatusMessage, Error>) -> Void) {
    completion(.success(currentStatus()))
  }

  /// Refreshes Apple readiness. Foundation Models does not expose app-triggered downloads.
  func ensureReady(
    policy: LocalAiInitializationPolicyMessage,
    completion: @escaping (Result<LocalAiStatusMessage, Error>) -> Void
  ) {
    let status = currentStatus()
    statusHandler.emit(status)
    completion(.success(status))
  }

  /// Creates a native Foundation Models session.
  func createSession(
    instructions: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          completion(.failure(PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )))
          return
        }

        let session = UUID().uuidString
        sessions[session] = LocalAiSession(instructions: instructions)
        completion(.success(session))
      } else {
        completion(.failure(PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )))
      }
    #else
      completion(.failure(PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )))
    #endif
  }

  /// Releases the native Foundation Models session.
  func disposeSession(
    session: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    streamHandler.cancel(session: session)
    sessions.removeValue(forKey: session)
    completion(.success(()))
  }

  /// Generates a complete response for one prompt.
  func generateText(
    session: String,
    prompt: String,
    config: LocalAiGenerationConfigMessage,
    completion: @escaping (Result<LocalAiGenerationResponseMessage, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          completion(.failure(PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )))
          return
        }

        guard let localSession = sessions[session] as? LocalAiSession else {
          completion(.failure(PigeonError(
            code: "local-ai-session-not-found",
            message: "The local AI session has already been disposed or was not created.",
            details: nil
          )))
          return
        }

        Task.detached(priority: .userInitiated) {
          let startTime = Date()

          do {
            let response: LanguageModelSession.Response<String>
            let options = GenerationOptions(
              temperature: config.temperature,
              maximumResponseTokens: config.maxTokens.map(Int.init)
            )

            response = try await localSession.modelSession.respond(to: prompt, options: options)

            DispatchQueue.main.async {
              completion(.success(LocalAiGenerationResponseMessage(
                text: response.content,
                tokenCount: nil,
                durationMs: Date().timeIntervalSince(startTime) * 1000
              )))
            }
          } catch {
            DispatchQueue.main.async {
              completion(.failure(PigeonError(
                code: "local-ai-generation-failed",
                message: error.localizedDescription,
                details: String(describing: error)
              )))
            }
          }
        }
      } else {
        completion(.failure(PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )))
      }
    #else
      completion(.failure(PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )))
    #endif
  }

  /// Starts a streaming response and returns chunks through the event channel.
  func startStreamingText(
    session: String,
    prompt: String,
    config: LocalAiGenerationConfigMessage,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let status = currentStatus()
        guard status.isAvailable else {
          completion(.failure(PigeonError(
            code: "local-ai-unavailable",
            message: status.reason,
            details: status.platformStatus
          )))
          return
        }

        guard let localSession = sessions[session] as? LocalAiSession else {
          completion(.failure(PigeonError(
            code: "local-ai-session-not-found",
            message: "The local AI session has already been disposed or was not created.",
            details: nil
          )))
          return
        }

        streamHandler.start(
          session: session,
          prompt: prompt,
          localSession: localSession,
          config: config
        )
        completion(.success(()))
      } else {
        completion(.failure(PigeonError(
          code: "local-ai-unsupported-os",
          message: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
          details: nil
        )))
      }
    #else
      completion(.failure(PigeonError(
        code: "local-ai-framework-unavailable",
        message: "FoundationModels.framework is not available in this SDK.",
        details: nil
      )))
    #endif
  }

  /// Cancels the active streaming generation task.
  func cancelStreamingText(session: String, completion: @escaping (Result<Void, Error>) -> Void) {
    streamHandler.cancel(session: session)
    completion(.success(()))
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
    sink?.success(status)
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
    private var currentTasks: [String: Task<Void, Never>] = [:]
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
        currentTasks[session]?.cancel()
        currentTasks[session] = nil
      }
    #endif
  }

  /// Cancels every active Foundation Models streaming task.
  func cancelAll() {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        currentTasks.values.forEach { $0.cancel() }
        currentTasks.removeAll()
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
      cancelAll()
      let temperature = config.temperature
      let maximumResponseTokens = config.maxTokens.map(Int.init)

      currentTasks[session] = Task.detached(priority: .userInitiated) { [weak self] in
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

            latestText = snapshot.content
            await MainActor.run {
              self?.sendChunk(text: latestText, isDone: false)
            }
          }

          await MainActor.run {
            self?.sendChunk(text: latestText, isDone: true)
          }
        } catch is CancellationError {
          await MainActor.run {
            self?.sendChunk(text: "", isDone: true)
          }
        } catch {
          await MainActor.run {
            self?.sendError(error)
          }
        }

        await MainActor.run {
          self?.currentTasks[session] = nil
        }
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
