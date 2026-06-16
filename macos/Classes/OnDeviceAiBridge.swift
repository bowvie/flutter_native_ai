import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Apple platform implementation of the Pigeon host API for Foundation Models.
///
/// The bridge is compiled even when the active SDK does not include
/// FoundationModels. Runtime availability checks keep unsupported OS versions
/// and unavailable model states out of the Dart UI layer.
final class OnDeviceAiBridge: OnDeviceAiHostApi {
  private var instructions = ""
  private let streamHandler = LocalAiGenerationStreamHandler()

  /// Registers the event-channel stream handler used by streaming generation.
  func registerStreamHandler(with messenger: FlutterBinaryMessenger) {
    GenerationStreamStreamHandler.register(
      with: messenger,
      streamHandler: streamHandler
    )
  }

  /// Returns the current Apple Foundation Models availability state.
  func availability(completion: @escaping (Result<LocalAiAvailabilityMessage, Error>) -> Void) {
    completion(.success(currentAvailability()))
  }

  /// Stores session instructions after confirming the model is available.
  func initialize(
    instructions: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let availability = currentAvailability()
    guard availability.isAvailable else {
      completion(.failure(PigeonError(
        code: "local-ai-unavailable",
        message: availability.reason,
        details: availability.modelStatus
      )))
      return
    }

    self.instructions = instructions
    completion(.success(()))
  }

  /// Generates a complete response for one prompt.
  func generateText(
    prompt: String,
    config: LocalAiGenerationConfigMessage,
    completion: @escaping (Result<LocalAiGenerationResponseMessage, Error>) -> Void
  ) {
    let availability = currentAvailability()
    guard availability.isAvailable else {
      completion(.failure(PigeonError(
        code: "local-ai-unavailable",
        message: availability.reason,
        details: availability.modelStatus
      )))
      return
    }

    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let instructions = self.instructions
        Task.detached(priority: .userInitiated) {
          let startTime = Date()

          do {
            let session = LanguageModelSession(instructions: instructions)
            let response: LanguageModelSession.Response<String>
            let options = GenerationOptions(
              temperature: config.temperature,
              maximumResponseTokens: config.maxTokens.map(Int.init)
            )

            response = try await session.respond(to: prompt, options: options)

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
    prompt: String,
    config: LocalAiGenerationConfigMessage,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let availability = currentAvailability()
    guard availability.isAvailable else {
      completion(.failure(PigeonError(
        code: "local-ai-unavailable",
        message: availability.reason,
        details: availability.modelStatus
      )))
      return
    }

    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        streamHandler.start(
          prompt: prompt,
          instructions: instructions,
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
  func cancelStreamingText(completion: @escaping (Result<Void, Error>) -> Void) {
    streamHandler.cancel()
    completion(.success(()))
  }

  /// Maps Foundation Models availability into a stable Pigeon message.
  private func currentAvailability() -> LocalAiAvailabilityMessage {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return LocalAiAvailabilityMessage(
            isAvailable: true,
            reason: nil,
            modelStatus: "available"
          )
        case .unavailable(let reason):
          return LocalAiAvailabilityMessage(
            isAvailable: false,
            reason: "Apple Foundation Models is unavailable: \(reason)",
            modelStatus: String(describing: reason)
          )
        @unknown default:
          return LocalAiAvailabilityMessage(
            isAvailable: false,
            reason: "Apple Foundation Models availability is unknown.",
            modelStatus: "unknown"
          )
        }
      }
    #endif

    return LocalAiAvailabilityMessage(
      isAvailable: false,
      reason: "Apple Foundation Models requires iOS 26.0 or macOS 26.0 or later.",
      modelStatus: "unsupported-os"
    )
  }
}

/// Event-channel handler that owns a single active streaming generation task.
final class LocalAiGenerationStreamHandler: GenerationStreamStreamHandler {
  private var sink: PigeonEventSink<LocalAiStreamChunkMessage>?

  #if canImport(FoundationModels)
    private var currentTask: Task<Void, Never>?
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
    cancel()
    sink = nil
  }

  /// Cancels the active Foundation Models task.
  func cancel() {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        currentTask?.cancel()
        currentTask = nil
      }
    #endif
  }

  #if canImport(FoundationModels)
    /// Starts a new Foundation Models streaming task.
    @available(iOS 26.0, macOS 26.0, *)
    func start(
      prompt: String,
      instructions: String,
      config: LocalAiGenerationConfigMessage
    ) {
      cancel()
      let temperature = config.temperature
      let maximumResponseTokens = config.maxTokens.map(Int.init)

      currentTask = Task.detached(priority: .userInitiated) { [weak self] in
        do {
          let session = LanguageModelSession(instructions: instructions)
          let options = GenerationOptions(
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
          )
          let stream = session.streamResponse(to: prompt, options: options)
          var latestText = ""

          for try await snapshot in stream {
            try Task.checkCancellation()

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
