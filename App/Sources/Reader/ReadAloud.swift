import AVFoundation
import ChickenKit
import MediaPlayer
import os
import SwiftUI

/// Reads the open book aloud from the paragraph on screen, turning pages as
/// it goes. It shows in Now Playing, answers the Lock Screen, Control
/// Center, and headphone controls, and keeps going with the screen off.
@Observable
final class ReadAloudController: NSObject {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
    }

    private(set) var state: State = .idle

    var speed: Double = ReadAloudController.savedSpeed {
        didSet {
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
            if state == .playing || state == .paused { restartCurrent() }
        }
    }

    static let speeds: [Double] = [0.8, 1, 1.2, 1.5, 1.8]

    @ObservationIgnored private weak var model: ReaderModel?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var passages: [SpokenPassage] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFetchCompletions: [() -> Void] = []
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeUtteranceID: ObjectIdentifier?
    @ObservationIgnored private var activeUtteranceGeneration = 0
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var cachedArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private lazy var voice = Self.bestVoice(for: model?.book.language)

    init(model: ReaderModel) {
        self.model = model
        super.init()
        synthesizer.delegate = self
    }

    isolated deinit {
        fetchTask?.cancel()
        artworkTask?.cancel()
        removeRemoteCommands()
        removeAudioObservers()
    }

    @ObservationIgnored private static weak var active: ReadAloudController?

    func start() {
        guard state == .idle, let engine = model?.engine else { return }
        if let other = Self.active, other !== self { other.stop() }
        Self.active = self
        generation += 1
        let startGeneration = generation
        state = .loading
        reachedEnd = false
        passages = []
        position = 0
        activateAudioSession()
        installAudioObservers()
        installRemoteCommands()
        loadArtworkIfNeeded()
        setReadingAloud(true)
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            let first = await engine.readAloudPassages(after: nil)
            guard let self, startGeneration == self.generation, self.state == .loading else { return }
            self.fetchTask = nil
            guard !first.isEmpty else {
                self.stop()
                return
            }
            self.passages = first
            self.position = 0
            self.state = .playing
            self.speakCurrent()
        }
    }

    func togglePause() {
        switch state {
        case .idle:
            start()
        case .loading:
            break
        case .playing:
            synthesizer.pauseSpeaking(at: .word)
            state = .paused
            updateNowPlaying()
        case .paused:
            if !synthesizer.continueSpeaking() { speakCurrent() }
            state = .playing
            updateNowPlaying()
        }
    }

    func skip(_ direction: Int) {
        guard state == .playing || state == .paused, !passages.isEmpty else { return }
        let target = position + direction
        guard target >= 0 else { restartCurrent(); return }
        if target < passages.count {
            position = target
            restartCurrent()
        } else if !reachedEnd {
            position = passages.count - 1
            fetchMore { [weak self] in
                guard let self, self.state == .playing || self.state == .paused,
                      self.position + 1 < self.passages.count else { return }
                self.position += 1
                self.restartCurrent()
            }
        }
    }

    func stop() {
        guard state != .idle else { return }
        generation += 1
        state = .idle
        activeUtteranceID = nil
        fetchTask?.cancel()
        fetchTask = nil
        pendingFetchCompletions.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        passages = []
        position = 0
        reachedEnd = false
        model?.engine?.endReadingAloud()
        removeRemoteCommands()
        removeAudioObservers()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #else
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        setReadingAloud(false)
    }

    private func speakCurrent() {
        guard passages.indices.contains(position) else { return }
        let passage = passages[position]
        let utterance = AVSpeechUtterance(string: passage.text)
        utterance.voice = voice
        utterance.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * speed)
            .clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.postUtteranceDelay = 0.12
        activeUtteranceID = ObjectIdentifier(utterance)
        activeUtteranceGeneration = generation
        model?.engine?.revealPassage(passage.id)
        synthesizer.speak(utterance)
        updateNowPlaying()
        if passages.count - position < 4 { fetchMore() }
    }

    private func restartCurrent() {
        generation += 1
        activeUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        if state == .paused { state = .playing }
        speakCurrent()
    }

    private func fetchMore(then completion: (() -> Void)? = nil) {
        if let completion { pendingFetchCompletions.append(completion) }
        guard fetchTask == nil, !reachedEnd, let engine = model?.engine, let last = passages.last else { return }
        let currentGeneration = generation
        fetchTask = Task { [weak self] in
            let more = await engine.readAloudPassages(after: last.id)
            guard let self, currentGeneration == self.generation, self.state != .idle else { return }
            self.fetchTask = nil
            if more.isEmpty {
                self.reachedEnd = true
            } else {
                self.passages.append(contentsOf: more)
            }
            let callbacks = self.pendingFetchCompletions
            self.pendingFetchCompletions.removeAll()
            callbacks.forEach { $0() }
        }
    }

    private func passageFinished(utteranceID: ObjectIdentifier) {
        guard state == .playing,
              activeUtteranceID == utteranceID,
              activeUtteranceGeneration == generation
        else { return }
        activeUtteranceID = nil
        if position + 1 < passages.count {
            position += 1
            speakCurrent()
        } else if reachedEnd {
            stop()
        } else {
            fetchMore { [weak self] in
                guard let self, self.state == .playing else { return }
                if self.position + 1 < self.passages.count {
                    self.position += 1
                    self.speakCurrent()
                } else {
                    self.stop()
                }
            }
        }
    }

    private func updateNowPlaying() {
        guard let model else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.chapters.isEmpty ? model.book.displayTitle : model.chapterTitle,
            MPMediaItemPropertyArtist: model.book.displayAuthor,
            MPMediaItemPropertyAlbumTitle: model.book.displayTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackProgress: model.book.progress,
        ]
        if let artwork = cachedArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = state == .playing ? .playing : .paused
        #endif
    }

    private func loadArtworkIfNeeded() {
        guard cachedArtwork == nil, artworkTask == nil,
              let model, let url = model.library.coverURL(for: model.book) else { return }
        artworkTask = Task { [weak self] in
            let data = await Self.renderArtworkJPEG(at: url)
            guard let self, !Task.isCancelled, let data, let image = PlatformImage(data: data) else { return }
            self.cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            if self.state != .idle { self.updateNowPlaying() }
        }
    }

    @concurrent
    private static func renderArtworkJPEG(at url: URL) async -> Data? {
        CoverRenderer.thumbnailJPEG(from: url, maxPixelSize: 600)
    }

    private func installRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping (ReadAloudController) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                guard self != nil else { return .noActionableNowPlayingItem }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    action(self)
                }
                return .success
            }
            remoteTargets.append((command, target))
        }
        on(center.playCommand) { if $0.state == .paused || $0.state == .idle { $0.togglePause() } }
        on(center.pauseCommand) { if $0.state == .playing { $0.togglePause() } }
        on(center.togglePlayPauseCommand) { $0.togglePause() }
        on(center.nextTrackCommand) { $0.skip(1) }
        on(center.previousTrackCommand) { $0.skip(-1) }
        on(center.stopCommand) { $0.stop() }
    }

    private func removeRemoteCommands() {
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
    }

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            ChickenLog.reader.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func installAudioObservers() {
        #if os(iOS)
        guard audioObservers.isEmpty else { return }
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    if self.state == .playing { self.togglePause() }
                case .ended:
                    if let optionsRaw,
                       AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume),
                       self.state == .paused {
                        self.togglePause()
                    }
                @unknown default: break
                }
            }
        })
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let reasonRaw,
                      AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable,
                      self.state == .playing else { return }
                self.togglePause()
            }
        })
        #endif
    }

    private func removeAudioObservers() {
        audioObservers.forEach(NotificationCenter.default.removeObserver)
        audioObservers = []
    }

    private func setReadingAloud(_ reading: Bool) {
        #if os(iOS)
        ReadingActivityController.shared.setReadingAloud(reading)
        #endif
    }

    private static let speedKey = "Chicken.readAloudSpeed"
    private static var savedSpeed: Double {
        let saved = UserDefaults.standard.double(forKey: speedKey)
        return saved > 0 ? saved : 1
    }

    private static func bestVoice(for language: String?) -> AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let rawCode = language.map { $0.replacingOccurrences(of: "_", with: "-") } ?? preferred
        let normalizedCode = Locale.Language(identifier: rawCode).languageCode?.identifier.lowercased()
            ?? String(rawCode.prefix(2)).lowercased()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            Locale.Language(identifier: $0.language).languageCode?.identifier.lowercased() == normalizedCode
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var value = voice.quality.rawValue * 10
            if voice.language == rawCode || voice.language == preferred { value += 5 }
            if voice.voiceTraits.contains(.isNoveltyVoice) { value -= 100 }
            return value
        }
        return candidates.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: normalizedCode)
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finishedID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.passageFinished(utteranceID: finishedID)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// The read-aloud strip above the progress bar: what's being read, back a
/// paragraph, play or pause, forward a paragraph, speed, and stop.
struct ReadAloudBar: View {
    @Environment(\.palette) private var palette
    let controller: ReadAloudController
    let chapter: String
    var compact = false

    private var isPlaying: Bool { controller.state == .playing }
    private var isLoading: Bool { controller.state == .loading }

    var body: some View {
        HStack(spacing: 2) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: isPlaying)
                    .foregroundStyle(palette.ribbon)
                    .frame(width: 34)
                    .accessibilityHidden(true)
            }

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isLoading ? "Starting…" : (isPlaying ? "Reading aloud" : "Paused"))
                        .font(.chickenUI(10.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                    Text(chapter)
                        .font(.chickenUI(13, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.trailing, 8)
            }

            control("Previous Paragraph", "backward.fill") { controller.skip(-1) }
                .disabled(isLoading)

            Button { controller.togglePause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(palette.background)
                    .frame(width: 38, height: 38)
                    .background(palette.text, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(TactilePressStyle())
            .disabled(isLoading)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [.option])

            control("Next Paragraph", "forward.fill") { controller.skip(1) }
                .disabled(isLoading)

            Menu {
                Picker("Speed", selection: Bindable(controller).speed) {
                    ForEach(ReadAloudController.speeds, id: \.self) { Text(Self.label(for: $0)).tag($0) }
                }
            } label: {
                Text(Self.label(for: controller.speed))
                    .font(.chickenUI(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(TactilePressStyle(scale: 0.94))
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Speed, \(Self.label(for: controller.speed))")

            control("Stop Reading Aloud", "xmark", size: 12, color: palette.muted) { controller.stop() }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .chickenGlass(in: Capsule())
    }

    private func control(_ title: String, _ symbol: String, size: CGFloat = 14, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color ?? palette.text)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle())
        .accessibilityLabel(title)
        .help(title)
    }

    private static func label(for speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed.formatted(.number.precision(.fractionLength(1))))×"
    }
}
