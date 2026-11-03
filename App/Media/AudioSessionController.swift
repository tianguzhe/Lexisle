import AVFoundation
import Foundation

/// Serializes potentially blocking audio-session changes away from the main thread.
/// The queue also keeps a previous stop from deactivating a newer playback request.
final class AudioSessionController: @unchecked Sendable {
    #if os(iOS)
    private let queue = DispatchQueue(label: "com.eenglish.wordatlas.audio-session")
    // Accessed only on queue.
    private var isActive = false
    #endif

    func activate() async throws {
        #if os(iOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    if !isActive {
                        let session = AVAudioSession.sharedInstance()
                        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                        try session.setActive(true)
                        isActive = true
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #endif
    }

    func deactivate() {
        #if os(iOS)
        queue.async { [self] in
            guard isActive else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        }
        #endif
    }
}
