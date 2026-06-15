package com.bowvie.flutter_native_ai

import android.os.SystemClock
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val LOCAL_AI_UNAVAILABLE = "local-ai-unavailable"
private const val LOCAL_AI_GENERATION_FAILED = "local-ai-generation-failed"
private const val DEFAULT_MAX_OUTPUT_TOKENS = 160
private const val ML_KIT_MAX_OUTPUT_TOKENS = 256

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
    private val streamHandler = LocalAiGenerationStreamHandler()
    @Volatile
    private var instructions = ""

    fun registerStreamHandler(messenger: BinaryMessenger) {
        GenerationStreamStreamHandler.register(messenger, streamHandler)
    }

    override fun availability(callback: (Result<LocalAiAvailabilityMessage>) -> Unit) {
        scope.launch {
            val availability = withContext(Dispatchers.Default) {
                currentAvailability()
            }
            callback(Result.success(availability))
        }
    }

    override fun initialize(instructions: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            val availability = withContext(Dispatchers.Default) {
                currentAvailability()
            }
            if (!availability.isAvailable) {
                callback(Result.failure(unavailableError(availability)))
                return@launch
            }

            this@OnDeviceAiBridge.instructions = instructions
            callback(Result.success(Unit))
        }
    }

    override fun generateText(
        prompt: String,
        config: LocalAiGenerationConfigMessage,
        callback: (Result<LocalAiGenerationResponseMessage>) -> Unit,
    ) {
        scope.launch {
            try {
                val result = withContext(Dispatchers.Default) {
                    val availability = currentAvailability()
                    if (!availability.isAvailable) {
                        throw unavailableError(availability)
                    }

                    val startTime = SystemClock.elapsedRealtimeNanos()
                    val response = generationClient.generateContent(
                        buildRequest(prompt, config, instructions),
                    )
                    val text = response.candidates.firstOrNull()?.text
                    if (text.isNullOrBlank()) {
                        throw FlutterError(
                            LOCAL_AI_GENERATION_FAILED,
                            "Gemini Nano returned no generated text.",
                            "No candidates returned by ML Kit Prompt API.",
                        )
                    }

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
        prompt: String,
        config: LocalAiGenerationConfigMessage,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch {
            val availability = withContext(Dispatchers.Default) {
                currentAvailability()
            }
            if (!availability.isAvailable) {
                callback(Result.failure(unavailableError(availability)))
                return@launch
            }

            streamHandler.start(
                prompt = prompt,
                instructions = instructions,
                config = config,
            )
            callback(Result.success(Unit))
        }
    }

    override fun cancelStreamingText(callback: (Result<Unit>) -> Unit) {
        streamHandler.cancel()
        callback(Result.success(Unit))
    }

    fun close() {
        streamHandler.close()
        scope.cancel()
    }

    private suspend fun currentAvailability(): LocalAiAvailabilityMessage {
        return try {
            when (val status = generationClient.checkStatus()) {
                FeatureStatus.AVAILABLE -> LocalAiAvailabilityMessage(
                    isAvailable = true,
                    reason = null,
                    modelStatus = "available",
                )
                FeatureStatus.DOWNLOADABLE -> LocalAiAvailabilityMessage(
                    isAvailable = false,
                    reason = "Gemini Nano is supported but the model is not downloaded yet.",
                    modelStatus = "downloadable",
                )
                FeatureStatus.DOWNLOADING -> LocalAiAvailabilityMessage(
                    isAvailable = false,
                    reason = "Gemini Nano is still downloading on this device.",
                    modelStatus = "downloading",
                )
                FeatureStatus.UNAVAILABLE -> LocalAiAvailabilityMessage(
                    isAvailable = false,
                    reason = "Gemini Nano is not available on this device.",
                    modelStatus = "unavailable",
                )
                else -> LocalAiAvailabilityMessage(
                    isAvailable = false,
                    reason = "Gemini Nano availability is unknown.",
                    modelStatus = status.toString(),
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            LocalAiAvailabilityMessage(
                isAvailable = false,
                reason = error.localizedMessage ?: "Gemini Nano availability could not be checked.",
                modelStatus = error.javaClass.simpleName,
            )
        }
    }

    private fun unavailableError(availability: LocalAiAvailabilityMessage): FlutterError {
        return FlutterError(
            LOCAL_AI_UNAVAILABLE,
            availability.reason,
            availability.modelStatus,
        )
    }

    private fun elapsedMillisSince(startTimeNanos: Long): Double {
        return (SystemClock.elapsedRealtimeNanos() - startTimeNanos) / 1_000_000.0
    }
}

private class LocalAiGenerationStreamHandler : GenerationStreamStreamHandler() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val generationClient = Generation.getClient()
    private var sink: PigeonEventSink<LocalAiStreamChunkMessage>? = null
    private var currentJob: Job? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<LocalAiStreamChunkMessage>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        cancel()
        sink = null
    }

    fun start(
        prompt: String,
        instructions: String,
        config: LocalAiGenerationConfigMessage,
    ) {
        cancel()

        currentJob = scope.launch {
            val latestText = StringBuilder()
            try {
                generationClient.generateContentStream(
                    buildRequest(prompt, config, instructions),
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
            } catch (error: CancellationException) {
                // Dart owns stream cancellation and closes the UI stream itself.
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
                if (currentJob == coroutineContext[Job]) {
                    currentJob = null
                }
            }
        }
    }

    fun cancel() {
        currentJob?.cancel()
        currentJob = null
    }

    fun close() {
        cancel()
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
    instructions: String,
) = generateContentRequest(TextPart(composePrompt(prompt, instructions))) {
    config.temperature?.let { temperature = it.toFloat() }
    maxOutputTokens = clampMaxOutputTokens(config.maxTokens)
}

private fun clampMaxOutputTokens(maxTokens: Long?): Int {
    val requestedTokens = maxTokens ?: DEFAULT_MAX_OUTPUT_TOKENS.toLong()
    return requestedTokens.coerceIn(1L, ML_KIT_MAX_OUTPUT_TOKENS.toLong()).toInt()
}

private fun composePrompt(prompt: String, instructions: String): String {
    if (instructions.isBlank()) {
        return prompt
    }

    return """
        Instructions:
        $instructions

        User request:
        $prompt
    """.trimIndent()
}
