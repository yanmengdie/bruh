import Foundation
import AVFoundation

@MainActor
final class MessageAudioPlaybackController: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var activeMessageId: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var loadingMessageId: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var resolvedDurations: [String: TimeInterval] = [:]

    private var player: AVAudioPlayer?
    private var prepareTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var prepareGeneration = 0

    func resolveDurationIfNeeded(
        for messageId: String,
        from url: URL,
        existingDuration: TimeInterval?
    ) async {
        if let existingDuration, existingDuration > 0 {
            resolvedDurations[messageId] = existingDuration
            return
        }

        if let cachedDuration = resolvedDurations[messageId], cachedDuration > 0 {
            return
        }

        do {
            let payload = try await playbackPayload(for: messageId, remoteURL: url)
            let duration = try playableDuration(from: payload)
            guard duration.isFinite, duration > 0 else { return }
            resolvedDurations[messageId] = duration
        } catch {
            return
        }
    }

    func togglePlayback(for messageId: String, url: URL) {
        if loadingMessageId == messageId {
            invalidatePreparation()
            cleanup()
            return
        }

        if activeMessageId == messageId, let player {
            if isPlaying {
                player.pause()
                stopProgressTimer()
                isPlaying = false
            } else {
                if player.play() {
                    startProgressTimer()
                    isPlaying = true
                } else {
                    failPlayback("Voice playback failed to start.")
                }
            }
            return
        }

        cleanup(resetState: false)
        activeMessageId = messageId
        loadingMessageId = messageId
        progress = 0
        isPlaying = false
        lastErrorMessage = nil
        prepareGeneration += 1
        let expectedGeneration = prepareGeneration

        prepareTask = Task { [weak self] in
            guard let self else { return }

            do {
                try configureAudioSession()
                print("[Voice] Preparing playback for \(messageId)")
                let player = try await preparePlayer(for: messageId, remoteURL: url)
                guard !Task.isCancelled else { return }
                guard self.prepareGeneration == expectedGeneration else { return }
                guard self.activeMessageId == messageId else { return }

                self.player = player
                self.prepareTask = nil
                self.loadingMessageId = nil
                self.resolvedDurations[messageId] = player.duration

                if player.play() {
                    print("[Voice] Started playback for \(messageId) (\(player.duration)s)")
                    self.isPlaying = true
                    self.startProgressTimer()
                } else {
                    self.failPlayback("Voice playback failed to start.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard self.prepareGeneration == expectedGeneration else { return }
                print("[Voice] Playback failed for \(messageId): \(error.localizedDescription)")
                self.prepareTask = nil
                self.failPlayback(userFacingErrorMessage(for: error))
            }
        }
    }

    func cleanup(resetState: Bool = true) {
        invalidatePreparation()

        stopProgressTimer()
        player?.pause()
        player = nil

        if resetState {
            activeMessageId = nil
            progress = 0
            isPlaying = false
            loadingMessageId = nil
            lastErrorMessage = nil
        } else {
            isPlaying = false
            loadingMessageId = nil
        }
    }

    deinit {
        prepareTask?.cancel()
    }

    private func invalidatePreparation() {
        prepareGeneration += 1
        prepareTask?.cancel()
        prepareTask = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func preparePlayer(for messageId: String, remoteURL: URL) async throws -> AVAudioPlayer {
        do {
            let payload = try await playbackPayload(for: messageId, remoteURL: remoteURL)
            return try makePlayer(from: payload)
        } catch {
            print("[Voice] Retrying fresh download for \(messageId)")
            let payload = try await playbackPayload(for: messageId, remoteURL: remoteURL, forceRedownload: true)
            return try makePlayer(from: payload)
        }
    }

    private func makePlayer(from payload: CachedVoicePayload) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: payload.data, fileTypeHint: payload.fileTypeHint)
        player.delegate = self
        player.volume = 1
        player.prepareToPlay()

        guard player.duration.isFinite, player.duration > 0.05 else {
            throw VoicePlaybackError.invalidAudioData
        }

        return player
    }

    private func playableDuration(from payload: CachedVoicePayload) throws -> TimeInterval {
        let player = try AVAudioPlayer(data: payload.data, fileTypeHint: payload.fileTypeHint)
        let duration = player.duration
        guard duration.isFinite, duration > 0.05 else {
            throw VoicePlaybackError.invalidAudioData
        }
        return duration
    }

    private func playbackPayload(
        for messageId: String,
        remoteURL: URL,
        forceRedownload: Bool = false
    ) async throws -> CachedVoicePayload {
        let cacheDirectory = try voiceCacheDirectory()
        let fileExtension = remoteURL.pathExtension.isEmpty ? "wav" : remoteURL.pathExtension.lowercased()
        let localURL = cacheDirectory.appendingPathComponent("\(messageId).\(fileExtension)")
        let fileManager = FileManager.default

        if forceRedownload, fileManager.fileExists(atPath: localURL.path) {
            try? fileManager.removeItem(at: localURL)
        }

        if !forceRedownload,
           fileManager.fileExists(atPath: localURL.path) {
            let cachedData = try Data(contentsOf: localURL)
            let cachedPayload = CachedVoicePayload(
                data: cachedData,
                fileTypeHint: audioFileTypeHint(mimeType: nil, remoteURL: remoteURL, data: cachedData),
                localURL: localURL
            )

            if isLikelyPlayableAudio(cachedPayload.data, mimeType: nil) {
                return cachedPayload
            }

            try? fileManager.removeItem(at: localURL)
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        request.setValue("audio/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoicePlaybackError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw VoicePlaybackError.httpStatus(httpResponse.statusCode)
        }

        let mimeType = httpResponse.mimeType?.lowercased()
        guard isLikelyPlayableAudio(data, mimeType: mimeType) else {
            throw VoicePlaybackError.invalidAudioData
        }

        try data.write(to: localURL, options: .atomic)
        return CachedVoicePayload(
            data: data,
            fileTypeHint: audioFileTypeHint(mimeType: mimeType, remoteURL: remoteURL, data: data),
            localURL: localURL
        )
    }

    private func voiceCacheDirectory() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = baseDirectory.appendingPathComponent("VoiceMessages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func startProgressTimer() {
        stopProgressTimer()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                let duration = player.duration
                guard duration.isFinite, duration > 0 else { return }
                self.progress = min(max(player.currentTime / duration, 0), 1)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func failPlayback(_ message: String) {
        cleanup(resetState: false)
        lastErrorMessage = message
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        if let voiceError = error as? VoicePlaybackError {
            return voiceError.message
        }
        return "Voice playback failed. Try tapping again."
    }

    private func isLikelyPlayableAudio(_ data: Data, mimeType: String?) -> Bool {
        guard data.count > 256 else { return false }

        if let mimeType, mimeType.hasPrefix("audio/") {
            return true
        }

        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12 {
            let waveHeader = Data([0x57, 0x41, 0x56, 0x45])
            return data.subdata(in: 8..<12) == waveHeader
        }

        if data.starts(with: [0x49, 0x44, 0x33]) {
            return true
        }

        if let firstByte = data.first, firstByte == 0xFF {
            return true
        }

        return false
    }

    private func audioFileTypeHint(mimeType: String?, remoteURL: URL, data: Data) -> String? {
        if let mimeType {
            switch mimeType {
            case "audio/wav", "audio/wave", "audio/x-wav":
                return AVFileType.wav.rawValue
            case "audio/mpeg", "audio/mp3":
                return AVFileType.mp3.rawValue
            case "audio/mp4", "audio/x-m4a", "audio/m4a":
                return AVFileType.m4a.rawValue
            default:
                break
            }
        }

        let fileExtension = remoteURL.pathExtension.lowercased()
        switch fileExtension {
        case "wav":
            return AVFileType.wav.rawValue
        case "mp3":
            return AVFileType.mp3.rawValue
        case "m4a", "mp4":
            return AVFileType.m4a.rawValue
        default:
            break
        }

        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12 {
            return AVFileType.wav.rawValue
        }
        if data.starts(with: [0x49, 0x44, 0x33]) || data.first == 0xFF {
            return AVFileType.mp3.rawValue
        }

        return nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let currentPlayer = self.player, player === currentPlayer else { return }
        stopProgressTimer()
        prepareTask = nil
        self.player = nil
        activeMessageId = nil
        progress = 0
        isPlaying = false
        loadingMessageId = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let currentPlayer = self.player, player === currentPlayer else { return }
        failPlayback(error?.localizedDescription ?? "Voice playback failed to decode.")
    }
}

struct CachedVoicePayload {
    let data: Data
    let fileTypeHint: String?
    let localURL: URL
}

enum VoicePlaybackError: Error {
    case invalidResponse
    case httpStatus(Int)
    case invalidAudioData

    var message: String {
        switch self {
        case .invalidResponse:
            return "Voice service returned an invalid response."
        case .httpStatus(let statusCode):
            return "Voice file request failed (\(statusCode))."
        case .invalidAudioData:
            return "Voice file is invalid or empty."
        }
    }
}
