package com.bowvie.flutter_native_ai

import android.os.SystemClock
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val LOCAL_AI_UNAVAILABLE = "local-ai-unavailable"
private const val LOCAL_AI_GENERATION_FAILED = "local-ai-generation-failed"
private const val DEFAULT_MAX_OUTPUT_TOKENS = 160
private const val ML_KIT_MAX_OUTPUT_TOKENS = 256

/** Maximum number of stored conversation messages (user + assistant turns). */
private const val MAX_HISTORY_MESSAGES = 20

/**
 * Android implementation of the Pigeon host API for Gemini Nano through ML Kit.
 *
 * The Dart service owns the reusable app contract. This bridge only translates
 * that contract into Android's on-device Prompt API and emits cumulative stream
 * snapshots to match the iOS Foundation Models bridge.
 */
class OnDeviceAiBridge : OnDeviceAiHostApi {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val generationClient = Generation.getClient()
    private val streamHandler = LocalAiGenerationStreamHandler(generationClient)
    private val statusHandler = LocalAiStatusStreamHandler()
    private val sessions = mutableMapOf<String, LocalAiSession>()
    private var initializationJob: Deferred<LocalAiStatusMessage>? = null

    fun registerStreamHandler(messenger: BinaryMessenger) {
        GenerationStreamStreamHandler.register(messenger, streamHandler)
        StatusStreamStreamHandler.register(messenger, statusHandler)
    }

    override fun status(callback: (Result<LocalAiStatusMessage>) -> Unit) {
        scope.launch {
            val status = withContext(Dispatchers.Default) {
                currentStatus()
            }
            callback(Result.success(status))
        }
    }

    override fun ensureReady(
        policy: LocalAiInitializationPolicyMessage,
        callback: (Result<LocalAiStatusMessage>) -> Unit,
    ) {
        scope.launch {
            try {
                if (policy == LocalAiInitializationPolicyMessage.NEVER) {
                    callback(Result.success(withContext(Dispatchers.Default) { currentStatus() }))
                    return@launch
                }

                val currentStatus = withContext(Dispatchers.Default) {
                    currentStatus()
                }
                if (currentStatus.isAvailable || !currentStatus.canInitialize) {
                    callback(Result.success(currentStatus))
                    return@launch
                }

                val job = initializationJob ?: async(Dispatchers.Default) {
                    initializeModel()
                }.also { deferred ->
                    initializationJob = deferred
                    deferred.invokeOnCompletion {
                        scope.launch {
                            if (initializationJob === deferred) {
                                initializationJob = null
                            }
                        }
                    }
                }

                callback(Result.success(job.await()))
            } catch (error: CancellationException) {
                callback(Result.failure(error))
            } catch (error: Throwable) {
                val failed = initializationFailedStatus(error)
                statusHandler.emit(failed)
                callback(Result.success(failed))
            }
        }
    }

    override fun createSession(instructions: String, callback: (Result<String>) -> Unit) {
        scope.launch {
            val status = withContext(Dispatchers.Default) {
                currentStatus()
            }
            if (!status.isAvailable) {
                callback(Result.failure(unavailableError(status)))
                return@launch
            }

            val session = UUID.randomUUID().toString()
            sessions[session] = LocalAiSession(instructions = instructions)
            callback(Result.success(session))
        }
    }

    override fun disposeSession(session: String, callback: (Result<Unit>) -> Unit) {
        streamHandler.cancel(session)
        sessions.remove(session)
        callback(Result.success(Unit))
    }

    override fun generateText(
        session: String,
        prompt: String,
        config: LocalAiGenerationConfigMessage,
        callback: (Result<LocalAiGenerationResponseMessage>) -> Unit,
    ) {
        scope.launch {
            try {
                val localSession = sessions[session]
                if (localSession == null) {
                    callback(Result.failure(sessionNotFoundError()))
                    return@launch
                }

                val result = withContext(Dispatchers.Default) {
                    val status = currentStatus()
                    if (!status.isAvailable) {
                        throw unavailableError(status)
                    }

                    val startTime = SystemClock.elapsedRealtimeNanos()
                    val response = generationClient.generateContent(
                        buildRequest(prompt, config, localSession),
                    )
                    val text = response.candidates.firstOrNull()?.text
                    if (text.isNullOrBlank()) {
                        throw FlutterError(
                            LOCAL_AI_GENERATION_FAILED,
                            "Gemini Nano returned no generated text.",
                            "No candidates returned by ML Kit Prompt API.",
                        )
                    }

                    localSession.record(prompt, text)
                    Result.success(
                        LocalAiGenerationResponseMessage(
                            text = text,
                            tokenCount = null,
                            durationMs = elapsedMillisSince(startTime),
                        ),
                    )
                }
                callback(result)
            } catch (error: CancellationException) {
                callback(Result.failure(error))
            } catch (error: FlutterError) {
                callback(Result.failure(error))
            } catch (error: Throwable) {
                callback(
                    Result.failure(
                        FlutterError(
                            LOCAL_AI_GENERATION_FAILED,
                            error.localizedMessage ?: "Gemini Nano generation failed.",
                            error.toString(),
                        ),
                    ),
                )
            }
        }
    }

    override fun startStreamingText(
        session: String,
        prompt: String,
        config: LocalAiGenerationConfigMessage,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch {
            val status = withContext(Dispatchers.Default) {
                currentStatus()
            }
            if (!status.isAvailable) {
                callback(Result.failure(unavailableError(status)))
                return@launch
            }

            val localSession = sessions[session]
            if (localSession == null) {
                callback(Result.failure(sessionNotFoundError()))
                return@launch
            }

            streamHandler.start(
                session = session,
                prompt = prompt,
                localSession = localSession,
                config = config,
            )
            callback(Result.success(Unit))
        }
    }

    override fun cancelStreamingText(session: String, callback: (Result<Unit>) -> Unit) {
        streamHandler.cancel(session)
        callback(Result.success(Unit))
    }

    fun close() {
        streamHandler.close()
        statusHandler.close()
        initializationJob?.cancel()
        initializationJob = null
        scope.cancel()
    }

    private suspend fun currentStatus(): LocalAiStatusMessage {
        return try {
            when (val status = generationClient.checkStatus()) {
                FeatureStatus.AVAILABLE -> LocalAiStatusMessage(
                    isSupported = true,
                    isReady = true,
                    canInitialize = false,
                    isInitializing = false,
                    reason = null,
                    platformStatus = "available",
                )
                FeatureStatus.DOWNLOADABLE -> LocalAiStatusMessage(
                    isSupported = true,
                    isReady = false,
                    canInitialize = true,
                    isInitializing = false,
                    reason = "Gemini Nano is supported but the model is not downloaded yet.",
                    platformStatus = "downloadable",
                )
                FeatureStatus.DOWNLOADING -> LocalAiStatusMessage(
                    isSupported = true,
                    isReady = false,
                    canInitialize = true,
                    isInitializing = true,
                    reason = "Gemini Nano is still downloading on this device.",
                    platformStatus = "downloading",
                )
                FeatureStatus.UNAVAILABLE -> LocalAiStatusMessage(
                    isSupported = false,
                    isReady = false,
                    canInitialize = false,
                    isInitializing = false,
                    reason = "Gemini Nano is not available on this device.",
                    platformStatus = "unavailable",
                )
                else -> LocalAiStatusMessage(
                    isSupported = false,
                    isReady = false,
                    canInitialize = false,
                    isInitializing = false,
                    reason = "Gemini Nano availability is unknown.",
                    platformStatus = status.toString(),
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            LocalAiStatusMessage(
                isSupported = false,
                isReady = false,
                canInitialize = false,
                isInitializing = false,
                reason = error.localizedMessage ?: "Gemini Nano availability could not be checked.",
                platformStatus = error.javaClass.simpleName,
            )
        }
    }

    private suspend fun initializeModel(): LocalAiStatusMessage {
        var totalBytes: Long? = null
        var latestStatus = currentStatus()
        var terminalStatus: LocalAiStatusMessage? = null
        statusHandler.emit(latestStatus.copy(isInitializing = true))

        try {
            generationClient.download().collect { status ->
                latestStatus = when (status) {
                    is DownloadStatus.DownloadStarted -> {
                        totalBytes = status.bytesToDownload.takeIf { it > 0 }
                        latestStatus.copy(
                            isInitializing = true,
                            initializationProgress = null,
                            platformStatus = "downloading",
                        )
                    }
                    is DownloadStatus.DownloadProgress -> {
                        val progress = totalBytes?.let { total ->
                            ((status.totalBytesDownloaded.toDouble() / total.toDouble()) * 100)
                                .toInt()
                                .coerceIn(0, 100)
                                .toLong()
                        }
                        latestStatus.copy(
                            isInitializing = true,
                            initializationProgress = progress,
                            platformStatus = "downloading",
                        )
                    }
                    is DownloadStatus.DownloadCompleted -> LocalAiStatusMessage(
                        isSupported = true,
                        isReady = true,
                        canInitialize = false,
                        isInitializing = false,
                        initializationProgress = 100L,
                        reason = null,
                        platformStatus = "available",
                    )
                    is DownloadStatus.DownloadFailed -> initializationFailedStatus(status.e)
                    else -> latestStatus
                }
                if (
                    status is DownloadStatus.DownloadCompleted ||
                    status is DownloadStatus.DownloadFailed
                ) {
                    terminalStatus = latestStatus
                }
                statusHandler.emit(latestStatus)
            }

            terminalStatus?.let { return it }
            val finalStatus = currentStatus()
            return if (finalStatus.isAvailable) {
                finalStatus.copy(initializationProgress = 100L)
            } else {
                finalStatus
            }.also { statusHandler.emit(it) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            return initializationFailedStatus(error).also { statusHandler.emit(it) }
        }
    }

    private fun initializationFailedStatus(error: Throwable): LocalAiStatusMessage {
        return LocalAiStatusMessage(
            isSupported = true,
            isReady = false,
            canInitialize = true,
            isInitializing = false,
            reason = error.localizedMessage ?: "Gemini Nano model initialization failed.",
            platformStatus = "initialization-failed",
        )
    }

    private fun unavailableError(status: LocalAiStatusMessage): FlutterError {
        return FlutterError(
            LOCAL_AI_UNAVAILABLE,
            status.reason,
            status.platformStatus,
        )
    }

    private fun sessionNotFoundError(): FlutterError {
        return FlutterError(
            "local-ai-session-not-found",
            "The local AI session has already been disposed or was not created.",
            null,
        )
    }

    private fun elapsedMillisSince(startTimeNanos: Long): Double {
        return (SystemClock.elapsedRealtimeNanos() - startTimeNanos) / 1_000_000.0
    }
}

private val LocalAiStatusMessage.isAvailable: Boolean
    get() = isSupported && isReady

private class LocalAiSession(
    private val instructions: String,
) {
    private val messages = mutableListOf<LocalAiMessage>()

    @Synchronized
    fun composePrompt(prompt: String): String {
        val builder = StringBuilder()
        if (instructions.isNotBlank()) {
            builder.appendLine("Instructions:")
            builder.appendLine(instructions)
            builder.appendLine()
        }
        if (messages.isNotEmpty()) {
            builder.appendLine("Previous conversation:")
            messages.forEach { message ->
                builder.appendLine("${message.role}: ${message.text}")
            }
            builder.appendLine()
        }
        builder.appendLine("User request:")
        builder.append(prompt)
        return builder.toString()
    }

    @Synchronized
    fun record(prompt: String, response: String) {
        messages.add(LocalAiMessage("User", prompt))
        messages.add(LocalAiMessage("Assistant", response))
        if (messages.size > MAX_HISTORY_MESSAGES) {
            messages.subList(0, messages.size - MAX_HISTORY_MESSAGES).clear()
        }
    }
}

private data class LocalAiMessage(val role: String, val text: String)

private class LocalAiStatusStreamHandler : StatusStreamStreamHandler() {
    private var sink: PigeonEventSink<LocalAiStatusMessage>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<LocalAiStatusMessage>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    suspend fun emit(status: LocalAiStatusMessage) {
        withContext(Dispatchers.Main.immediate) {
            sink?.success(status)
        }
    }

    fun close() {
        sink = null
    }
}

private class LocalAiGenerationStreamHandler(
    private val generationClient: GenerativeModel,
) : GenerationStreamStreamHandler() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var sink: PigeonEventSink<LocalAiStreamChunkMessage>? = null
    private val currentJobs = ConcurrentHashMap<String, Job>()

    override fun onListen(p0: Any?, sink: PigeonEventSink<LocalAiStreamChunkMessage>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        cancelAll()
        sink = null
    }

    fun start(
        session: String,
        prompt: String,
        localSession: LocalAiSession,
        config: LocalAiGenerationConfigMessage,
    ) {
        // Streaming chunks share a single event channel without a session id, so
        // only one generation may stream at a time per plugin instance. Cancel
        // any in-flight stream (for this or another session) before starting.
        cancelAll()

        currentJobs[session] = scope.launch {
            val latestText = StringBuilder()
            try {
                generationClient.generateContentStream(
                    buildRequest(prompt, config, localSession),
                ).collect { chunk ->
                    latestText.append(chunk.candidates.firstOrNull()?.text.orEmpty())
                    emit(
                        LocalAiStreamChunkMessage(
                            text = latestText.toString(),
                            isDone = false,
                        ),
                    )
                }

                emit(
                    LocalAiStreamChunkMessage(
                        text = latestText.toString(),
                        isDone = true,
                    ),
                )
                localSession.record(prompt, latestText.toString())
            } catch (error: CancellationException) {
                // Cancellation can be initiated natively (e.g. disposeSession or
                // a new stream starting). Emit a terminal chunk in a
                // non-cancellable context so any active Dart listener completes
                // deterministically instead of hanging.
                withContext(NonCancellable) {
                    emit(
                        LocalAiStreamChunkMessage(
                            text = latestText.toString(),
                            isDone = true,
                        ),
                    )
                }
            } catch (error: Throwable) {
                emit(
                    LocalAiStreamChunkMessage(
                        text = latestText.toString(),
                        isDone = true,
                        errorCode = LOCAL_AI_GENERATION_FAILED,
                        errorMessage = error.localizedMessage ?: "Gemini Nano generation failed.",
                    ),
                )
            } finally {
                currentJobs.remove(session, coroutineContext[Job])
            }
        }
    }

    fun cancel(session: String) {
        currentJobs.remove(session)?.cancel()
    }

    fun cancelAll() {
        currentJobs.values.forEach { it.cancel() }
        currentJobs.clear()
    }

    fun close() {
        cancelAll()
        scope.cancel()
        sink = null
    }

    private suspend fun emit(chunk: LocalAiStreamChunkMessage) {
        withContext(Dispatchers.Main.immediate) {
            sink?.success(chunk)
        }
    }
}

private fun buildRequest(
    prompt: String,
    config: LocalAiGenerationConfigMessage,
    session: LocalAiSession,
) = generateContentRequest(TextPart(session.composePrompt(prompt))) {
    config.temperature?.let { temperature = it.toFloat() }
    maxOutputTokens = clampMaxOutputTokens(config.maxTokens)
}

private fun clampMaxOutputTokens(maxTokens: Long?): Int {
    val requestedTokens = maxTokens ?: DEFAULT_MAX_OUTPUT_TOKENS.toLong()
    return requestedTokens.coerceIn(1L, ML_KIT_MAX_OUTPUT_TOKENS.toLong()).toInt()
}
