//  SpeechService.swift
//  On-device speech to text for voice set logging: SpeechAnalyzer + SpeechTranscriber (iOS 26).
//  Audio comes from AVAudioEngine, is converted to the analyzer's format, and streamed in.
//  The transcript is only text: VoiceSetParser turns it into numbers, and the user confirms.

import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class SpeechService {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case stopped
        case failed(Failure)
    }

    enum Failure: Equatable {
        case noPermission
        case unsupported
        case audio
    }

    private(set) var state: State = .idle
    /// Finalized text plus the in-progress (volatile) text.
    private(set) var transcript = ""
    /// 0…1 input level for the waveform.
    private(set) var level: Double = 0

    private var finalized = ""
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var capture: AudioCapture?
    private var resultsTask: Task<Void, Never>?

    var isListening: Bool { state == .listening || state == .preparing }

    /// Words the transcriber should expect.
    private static let vocabulary = ["reps", "kilos", "kg", "pounds", "lbs", "same weight", "bodyweight", "and a half"]

    func start() async {
        guard !isListening else { return }
        reset()
        state = .preparing

        guard AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            state = .failed(.noPermission); return
        }
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard SpeechTranscriber.isAvailable, let locale else {
            state = .failed(.unsupported); return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            state = .failed(.unsupported); return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            state = .failed(.unsupported); return
        }
        let context = AnalysisContext()
        context.contextualStrings[.general] = Self.vocabulary
        try? await analyzer.setContext(context)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.continuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.receive(text, isFinal: result.isFinal)
                }
            } catch {
                // Cancelled or finished: the transcript so far stays.
            }
        }

        do {
            try Self.activateSession()
            let capture = AudioCapture(format: format)
            try capture.start(
                onBuffer: { buffer in continuation.yield(AnalyzerInput(buffer: buffer)) },
                onLevel: { [weak self] value in Task { @MainActor in self?.level = value } }
            )
            self.capture = capture
            try await analyzer.start(inputSequence: stream)
            state = .listening
        } catch {
            await cancel()
            state = .failed(.audio)
        }
    }

    /// Stops listening and waits for the last words to be finalized.
    func stop() async {
        guard isListening else { return }
        capture?.stop()
        capture = nil
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        teardown()
        state = .stopped
    }

    /// Stops at once, dropping anything not yet transcribed (sheet closed).
    func cancel() async {
        capture?.stop()
        capture = nil
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        teardown()
        if isListening { state = .idle }
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += (finalized.isEmpty ? "" : " ") + text.trimmingCharacters(in: .whitespaces)
            transcript = finalized
        } else {
            transcript = [finalized, text.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private func reset() {
        finalized = ""
        transcript = ""
        level = 0
    }

    private func teardown() {
        analyzer = nil
        resultsTask = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Mixes with music so the gym playlist keeps going.
    private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)
    }
}

/// Microphone tap → converted buffers. Runs its callbacks on the audio thread.
private final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var onLevel: (@Sendable (Double) -> Void)?

    init(format: AVAudioFormat) {
        self.format = format
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               onLevel: @escaping @Sendable (Double) -> Void) throws {
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw CaptureError.noInput }
        if inputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [self] buffer, _ in
            handle(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(Self.level(of: buffer))
        guard let converter else { onBuffer?(buffer); return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        let feed = Feed(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            feed.next(status)
        }
        if error == nil, output.frameLength > 0 { onBuffer?(output) }
    }

    /// RMS of the first channel mapped from −50…0 dB to 0…1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        return Double(min(max((db + 50) / 50, 0), 1))
    }

    /// Hands the converter one buffer, then reports "no data now".
    private final class Feed: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            guard let b = buffer else { status.pointee = .noDataNow; return nil }
            buffer = nil
            status.pointee = .haveData
            return b
        }
    }

    enum CaptureError: Error { case noInput }
}
