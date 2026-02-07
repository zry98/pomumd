//
//  ConnectionState.swift
//  pomumd
//
//  State machines for managing TTS and STT connection states.
//  Replaces boolean flags with enum-based states to prevent impossible states.
//

import Foundation
import AVFoundation

// Note: AudioFormat is defined in Models/AudioFormat.swift

// MARK: - TTS Streaming State

/// State machine for TTS streaming operations
enum TTSStreamingState: Equatable {
    case idle
    case streaming(StreamingContext)

    /// Context data for active streaming session
    struct StreamingContext: Equatable {
        var textBuffer: String
        var voiceIdentifier: String?
        var audioStreamStarted: Bool
        var pendingTask: TaskIdentifier?
        var audioFormat: AudioFormat?
        var ssmlMode: Bool

        init(
            textBuffer: String = "",
            voiceIdentifier: String? = nil,
            audioStreamStarted: Bool = false,
            pendingTask: TaskIdentifier? = nil,
            audioFormat: AudioFormat? = nil,
            ssmlMode: Bool = false
        ) {
            self.textBuffer = textBuffer
            self.voiceIdentifier = voiceIdentifier
            self.audioStreamStarted = audioStreamStarted
            self.pendingTask = pendingTask
            self.audioFormat = audioFormat
            self.ssmlMode = ssmlMode
        }
    }

    /// Identifier for tracking async tasks
    struct TaskIdentifier: Equatable, Hashable {
        let id: UUID

        init() {
            self.id = UUID()
        }
    }

    // MARK: - State Transition Methods

    /// Start a new streaming session
    mutating func startStreaming(voiceIdentifier: String?) {
        self = .streaming(StreamingContext(voiceIdentifier: voiceIdentifier))
    }

    /// Append text to the current streaming buffer
    mutating func appendText(_ text: String) {
        guard case .streaming(var context) = self else { return }
        context.textBuffer += text
        self = .streaming(context)
    }

    /// Update the text buffer (replace, not append)
    mutating func updateTextBuffer(_ newBuffer: String) {
        guard case .streaming(var context) = self else { return }
        context.textBuffer = newBuffer
        self = .streaming(context)
    }

    /// Enable or disable SSML mode
    mutating func setSSMLMode(_ enabled: Bool) {
        guard case .streaming(var context) = self else { return }
        context.ssmlMode = enabled
        self = .streaming(context)
    }

    /// Mark that audio streaming has started with the given format
    mutating func markAudioStreamStarted(format: AudioFormat) {
        guard case .streaming(var context) = self else { return }
        context.audioStreamStarted = true
        context.audioFormat = format
        self = .streaming(context)
    }

    /// Set or clear the pending task identifier
    mutating func setPendingTask(_ taskId: TaskIdentifier?) {
        guard case .streaming(var context) = self else { return }
        context.pendingTask = taskId
        self = .streaming(context)
    }

    /// Reset to idle state
    mutating func reset() {
        self = .idle
    }

    // MARK: - Query Methods

    /// Check if currently streaming
    var isStreaming: Bool {
        if case .streaming = self {
            return true
        }
        return false
    }

    /// Get the current streaming context, if any
    var context: StreamingContext? {
        if case .streaming(let context) = self {
            return context
        }
        return nil
    }
}

// MARK: - STT State

/// State machine for STT (Speech-to-Text) operations
enum STTState: Equatable {
    case idle
    case collectingAudio(AudioContext)

    /// Context data for active audio collection session
    struct AudioContext: Equatable {
        var buffer: Data
        var language: String?
        var sampleRate: UInt32
        var channels: UInt32
        var width: UInt32

        init(
            buffer: Data = Data(),
            language: String? = nil,
            sampleRate: UInt32 = 16000,
            channels: UInt32 = 1,
            width: UInt32 = 2
        ) {
            self.buffer = buffer
            self.language = language
            self.sampleRate = sampleRate
            self.channels = channels
            self.width = width
        }
    }

    // MARK: - State Transition Methods

    /// Start a new transcription session
    mutating func startTranscription(language: String?) {
        self = .collectingAudio(AudioContext(language: language))
    }

    /// Update audio format parameters
    mutating func updateAudioFormat(sampleRate: UInt32, channels: UInt32, width: UInt32) {
        guard case .collectingAudio(var context) = self else { return }
        context.sampleRate = sampleRate
        context.channels = channels
        context.width = width
        self = .collectingAudio(context)
    }

    /// Append audio data to the buffer
    mutating func appendAudio(_ data: Data) {
        guard case .collectingAudio(var context) = self else { return }
        context.buffer.append(data)
        self = .collectingAudio(context)
    }

    /// Reset to idle state
    mutating func reset() {
        self = .idle
    }

    // MARK: - Query Methods

    /// Check if currently collecting audio
    var isCollecting: Bool {
        if case .collectingAudio = self {
            return true
        }
        return false
    }

    /// Get the current audio context, if any
    var context: AudioContext? {
        if case .collectingAudio(let context) = self {
            return context
        }
        return nil
    }
}
