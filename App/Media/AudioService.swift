import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AudioService: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = AudioService()

    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var sourceLabel = ""
    private(set) var errorMessage: String?

    @ObservationIgnored private let audioSession = AudioSessionController()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playerID: ObjectIdentifier?
    @ObservationIgnored private var utteranceID: ObjectIdentifier?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var speechStarted: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var speechTimeout: Task<Void, Never>?
    @ObservationIgnored private var observations: [NotificationObservation] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        observeAudioInterruptions()
    }

    /// Returns true once playback starts. Cancellation is silent; unavailable audio also sets errorMessage.
    @discardableResult
    func play(word: VocabularyEntry, kind: MediaKind, accent: Accent) async -> Bool {
        stop()
        let requestID = generation
        let content = SpokenContent(word: word, kind: kind, accent: accent)
        errorMessage = nil
        isLoading = true
        sourceLabel = "正在载入…"

        do {
            let url = try await MediaRepository.shared.localURL(wordID: word.id, kind: kind)
            guard isCurrent(requestID) else {
                if generation == requestID { stop() }
                return false
            }
            try await audioSession.activate()
            guard isCurrent(requestID) else {
                if generation == requestID { stop() }
                return false
            }
            try startRecording(at: url, accent: content.accent)
            return true
        } catch {
            guard isCurrent(requestID) else {
                if generation == requestID { stop() }
                return false
            }
            clearRecording()
        }
        return await startSpeech(content, requestID: requestID)
    }

    func stop() {
        generation = UUID()
        clearRecording()
        let hadSpeech = utteranceID != nil
        utteranceID = nil
        if hadSpeech {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resolveSpeechStart(false)
        isPlaying = false
        isLoading = false
        audioSession.deactivate()
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        generation == requestID && !Task.isCancelled
    }

    private func startRecording(at url: URL, accent: Accent) throws {
        let recording = try AVAudioPlayer(contentsOf: url)
        recording.delegate = self
        recording.prepareToPlay()
        player = recording
        playerID = ObjectIdentifier(recording)
        guard recording.play() else { throw MediaError.invalidMedia }
        isPlaying = true
        isLoading = false
        sourceLabel = accent == .uk ? "英音 · 原声录音" : "美音 · 原声录音"
    }

    private func startSpeech(_ content: SpokenContent, requestID: UUID) async -> Bool {
        guard let voice = preferredVoice(for: content.accent) else {
            failPlayback("录音未缓存，且设备没有可用的英语语音。联网后可重试。")
            return false
        }
        do {
            try await audioSession.activate()
        } catch {
            guard isCurrent(requestID) else {
                if generation == requestID { stop() }
                return false
            }
            failPlayback("音频设备暂时不可用，请稍后重试。")
            return false
        }
        guard isCurrent(requestID) else {
            if generation == requestID { stop() }
            return false
        }

        sourceLabel = "系统语音 · \(voice.language == "en-GB" ? "英音" : voice.language == "en-US" ? "美音" : "英语")"
        let utterance = AVSpeechUtterance(string: content.text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utteranceID = ObjectIdentifier(utterance)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                speechStarted = continuation
                synthesizer.speak(utterance)
                speechTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard let self, self.generation == requestID, self.speechStarted != nil else { return }
                    self.failPlayback("系统语音未能开始播放，请检查设备的英语语音设置。")
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestID else { return }
                self.stop()
            }
        }
    }

    private func preferredVoice(for accent: Accent) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let matching = voices.filter { $0.language == accent.language }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return matching.first ?? voices.first { $0.language.hasPrefix("en-") }
    }

    private func clearRecording() {
        playerID = nil
        player?.stop()
        player = nil
    }

    private func resolveSpeechStart(_ started: Bool) {
        speechTimeout?.cancel()
        speechTimeout = nil
        speechStarted?.resume(returning: started)
        speechStarted = nil
    }

    private func failPlayback(_ message: String) {
        stop()
        sourceLabel = "语音暂不可用"
        errorMessage = message
    }

    private struct SpokenContent {
        let text: String
        let accent: Accent

        init(word: VocabularyEntry, kind: MediaKind, accent: Accent) {
            switch kind {
            case .example: text = word.examples.first?.en ?? word.word
            case .example2: text = word.examples.dropFirst().first?.en ?? word.word
            default: text = word.word
            }
            self.accent = kind == .uk ? .uk : kind == .us ? .us : accent
        }
    }

    private func observeAudioInterruptions() {
        #if os(iOS)
        let interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }
        let route = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }
        observations = [NotificationObservation(token: interruption), NotificationObservation(token: route)]
        #endif
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.playerID == identifier else { return }
            self.clearRecording()
            self.isPlaying = false
            self.audioSession.deactivate()
            if !flag { self.errorMessage = "录音播放中断，请重试。" }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.playerID == identifier else { return }
            self.stop()
            self.errorMessage = "录音解码失败，请重试或清理媒体缓存。"
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.isLoading = false
            self.isPlaying = true
            self.resolveSpeechStart(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeech(identifier: ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeech(identifier: ObjectIdentifier(utterance))
    }

    private nonisolated func finishSpeech(identifier: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.utteranceID = nil
            self.isPlaying = false
            self.isLoading = false
            self.resolveSpeechStart(false)
            self.audioSession.deactivate()
        }
    }
}
