import AVFoundation
import ChickenKit
import MediaPlayer
import SwiftUI

/// Reads the open book aloud from the paragraph on screen, turning pages as
/// it goes. It shows in Now Playing, answers the Lock Screen, Control
/// Center, and headphone controls, and keeps going with the screen off.
@Observable
final class ReadAloudController: NSObject {
    enum State { case idle, playing, paused }

    private(set) var state: State = .idle
    /// Speaking rate as a multiple of the voice's natural pace.
    var speed: Double = ReadAloudController.savedSpeed {
        didSet {
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
            if state != .idle { restartCurrent() }
        }
    }

    static let speeds: [Double] = [0.8, 1, 1.2, 1.5, 1.8]

    @ObservationIgnored private weak var model: ReaderModel?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var passages: [SpokenPassage] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var reachedEnd = false
    /// Bumped whenever speech is stopped on purpose, so callbacks from the
    /// cancelled utterance are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private lazy var voice = Self.bestVoice(for: model?.book.language)

    init(model: ReaderModel) {
        self.model = model
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Controls

    /// One voice at a time: starting a book stops any other reading aloud.
    @ObservationIgnored private static weak var active: ReadAloudController?

    func start() {
        guard state == .idle, let engine = model?.engine else { return }
        if let other = Self.active, other !== self { other.stop() }
        Self.active = self
        state = .playing
        reachedEnd = false
        activateAudioSession()
        installRemoteCommands()
        setReadingAloud(true)
        let generation = self.generation
        Task {
            let first = await engine.readAloudPassages(after: nil)
            guard generation == self.generation, state != .idle else { return }
            guard !first.isEmpty else { stop(); return }
            passages = first
            position = 0
            speakCurrent()
        }
    }

    func togglePause() {
        switch state {
        case .idle: start()
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
        guard state != .idle else { return }
        let target = position + direction
        guard target >= 0 else { restartCurrent(); return }
        if target < passages.count {
            position = target
            restartCurrent()
        } else if !reachedEnd {
            position = passages.count - 1
            fetchMore { [weak self] in
                guard let self, self.position + 1 < self.passages.count else { return }
                self.position += 1
                self.restartCurrent()
            }
        }
    }

    func stop() {
        guard state != .idle else { return }
        generation += 1
        state = .idle
        synthesizer.stopSpeaking(at: .immediate)
        passages = []
        position = 0
        model?.engine?.endReadingAloud()
        removeRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #else
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        setReadingAloud(false)
    }

    // MARK: Speaking

    private func speakCurrent() {
        guard passages.indices.contains(position) else { return }
        let passage = passages[position]
        let utterance = AVSpeechUtterance(string: passage.text)
        utterance.voice = voice
        utterance.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * speed)
            .clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.postUtteranceDelay = 0.12
        model?.engine?.revealPassage(passage.id)
        synthesizer.speak(utterance)
        updateNowPlaying()
        // Keep a few passages queued ahead.
        if passages.count - position < 4 { fetchMore() }
    }

    private func restartCurrent() {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        if state == .paused { state = .playing }
        speakCurrent()
    }

    private func fetchMore(then completion: (() -> Void)? = nil) {
        guard !isFetching, !reachedEnd, let engine = model?.engine, let last = passages.last else { return }
        isFetching = true
        Task {
            let more = await engine.readAloudPassages(after: last.id)
            isFetching = false
            guard state != .idle else { return }
            if more.isEmpty { reachedEnd = true } else { passages.append(contentsOf: more) }
            completion?()
        }
    }

    private func passageFinished(generation finished: Int) {
        guard finished == generation, state == .playing else { return }
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

    // MARK: Now Playing

    private func updateNowPlaying() {
        guard let model else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.chapters.isEmpty ? model.book.title : model.chapterTitle,
            MPMediaItemPropertyArtist: model.book.displayAuthor,
            MPMediaItemPropertyAlbumTitle: model.book.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackProgress: model.book.progress,
        ]
        if let artwork = artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = state == .playing ? .playing : .paused
        #endif
    }

    @ObservationIgnored private lazy var artwork: MPMediaItemArtwork? = {
        guard let model, let url = model.library.coverURL(for: model.book),
              let data = CoverRenderer.thumbnailJPEG(from: url, maxPixelSize: 600),
              let image = PlatformImage(data: data)
        else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    private func installRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (ReadAloudController) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                guard let self else { return .noActionableNowPlayingItem }
                MainActor.assumeIsolated { action(self) }
                return .success
            }
            remoteTargets.append((command, target))
        }
        on(center.playCommand) { if $0.state != .playing { $0.togglePause() } }
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
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    private func setReadingAloud(_ reading: Bool) {
        #if os(iOS)
        ReadingActivityController.shared.setReadingAloud(reading)
        #endif
    }

    // MARK: Voice

    private static let speedKey = "Chicken.readAloudSpeed"
    private static var savedSpeed: Double {
        let saved = UserDefaults.standard.double(forKey: speedKey)
        return saved > 0 ? saved : 1
    }

    /// The best-sounding installed voice for the book's language: premium,
    /// then enhanced, preferring the user's own region for that language.
    private static func bestVoice(for language: String?) -> AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let code = language.map { $0.replacingOccurrences(of: "_", with: "-") } ?? preferred
        let base = String(code.prefix(2)).lowercased()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(base) }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var value = voice.quality.rawValue * 10
            if voice.language == code || voice.language == preferred { value += 5 }
            if voice.voiceTraits.contains(.isNoveltyVoice) { value -= 100 }
            return value
        }
        return candidates.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: code)
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.passageFinished(generation: self.generation)
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

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: isPlaying)
                .foregroundStyle(palette.ribbon)
                .frame(width: 30)
                .accessibilityHidden(true)

            if !compact {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isPlaying ? "Reading aloud" : "Paused")
                        .font(.chickenUI(10.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                    Text(chapter)
                        .font(.chickenSerif(13.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.trailing, 10)
            }

            control("Previous Paragraph", "backward.fill") { controller.skip(-1) }

            Button { controller.togglePause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(palette.background)
                    .frame(width: 36, height: 36)
                    .background(palette.text, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [.option])

            control("Next Paragraph", "forward.fill") { controller.skip(1) }

            Menu {
                Picker("Speed", selection: Bindable(controller).speed) {
                    ForEach(ReadAloudController.speeds, id: \.self) { Text(Self.label(for: $0)).tag($0) }
                }
            } label: {
                Text(Self.label(for: controller.speed))
                    .font(.chickenUI(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 40, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Speed, \(Self.label(for: controller.speed))")

            control("Stop Reading Aloud", "xmark", size: 12, color: palette.muted) { controller.stop() }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
    }

    private func control(_ title: String, _ symbol: String, size: CGFloat = 14, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color ?? palette.text)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private static func label(for speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed.formatted(.number.precision(.fractionLength(1))))×"
    }
}
