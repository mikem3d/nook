import AVFoundation
import Speech

/// Microphone in, text out. Owns the audio engine and the recognition task for one utterance;
/// both exist only between `start` and the final transcript, so nothing runs while idle and the
/// microphone indicator goes out the moment the key is released.
final class VoiceCapture {
    enum Problem: Equatable {
        /// Not running from the .app bundle: asking for access without usage strings kills the process.
        case needsBundle
        case microphoneDenied
        case speechDenied
        case noMicrophone
        case unsupportedLocale(String)
        /// Only network recognition exists for this language and the user has not allowed it.
        case onDeviceUnavailable(String)
        case unavailable
        case failed(String)

        var message: String {
            switch self {
            case .needsBundle: return "Voice needs the app bundle. Run scripts/run.sh instead of swift run."
            case .microphoneDenied: return "Nook can't use the microphone. Click to open Privacy settings."
            case .speechDenied: return "Speech recognition is off for Nook. Click to open Privacy settings."
            case .noMicrophone: return "No microphone found."
            case .unsupportedLocale(let id): return "Speech recognition doesn't support \(id)."
            case .onDeviceUnavailable(let id):
                return "No on-device recognition for \(id). Click to add it under Dictation."
            case .unavailable: return "Speech recognition isn't available right now."
            case .failed(let why): return "Couldn't start listening: \(why)"
            }
        }

        /// The System Settings pane that fixes it, when there is one.
        var settingsURL: URL? {
            switch self {
            case .microphoneDenied: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            case .speechDenied: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            case .onDeviceUnavailable: return URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            default: return nil
            }
        }
    }

    enum Access {
        case ready
        /// Granted just now through the system prompts; the key was surely released meanwhile.
        case readyAfterPrompt
        case blocked(Problem)
    }

    /// Audio is never sent to Apple's servers unless this is set.
    static let allowNetworkKey = "nook.voice.allowNetwork"
    /// A BCP 47 identifier such as "en-GB"; defaults to the system language.
    static let localeKey = "nook.voice.locale"

    /// 0...1, roughly 20 to 45 times a second while listening. Main thread, like all callbacks.
    var onLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?
    /// The best transcript once the utterance is over; empty if nothing was heard.
    var onFinish: ((String) -> Void)?

    private(set) var isBusy = false

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var timeout: Timer?
    /// Bumped per utterance so a late callback from an old task cannot touch a new one.
    private var generation = 0

    // MARK: access

    /// Asks for microphone, then speech recognition, only if not yet decided. Completion on main.
    func requestAccess(_ completion: @escaping (Access) -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["NSMicrophoneUsageDescription"] != nil, info["NSSpeechRecognitionUsageDescription"] != nil else {
            return completion(.blocked(.needsBundle))
        }
        var prompted = false
        func speech() {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: completion(prompted ? .readyAfterPrompt : .ready)
            case .notDetermined:
                prompted = true
                SFSpeechRecognizer.requestAuthorization { status in
                    DispatchQueue.main.async {
                        completion(status == .authorized ? .readyAfterPrompt : .blocked(.speechDenied))
                    }
                }
            default: completion(.blocked(.speechDenied))
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: speech()
        case .notDetermined:
            prompted = true
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { speech() } else { completion(.blocked(.microphoneDenied)) }
                }
            }
        default: completion(.blocked(.microphoneDenied))
        }
    }

    // MARK: one utterance

    /// `vocabulary` biases recognition toward words it would otherwise mangle (agent names).
    func start(vocabulary: [String]) -> Problem? {
        guard !isBusy else { return nil }
        let defaults = UserDefaults.standard
        let locale = defaults.string(forKey: Self.localeKey).map(Locale.init(identifier:)) ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return .unsupportedLocale(locale.identifier) }
        guard recognizer.supportsOnDeviceRecognition || defaults.bool(forKey: Self.allowNetworkKey) else {
            return .onDeviceUnavailable(locale.identifier)
        }
        guard recognizer.isAvailable else { return .unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return .noMicrophone }
        let onLevel = self.onLevel
        // Runs on the audio thread: append, measure, hop to main. `request` is captured directly
        // so the block never touches `self`.
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            // -50 dB...-10 dB mapped to 0...1: speech fills the meter, room noise barely moves it.
            let level = max(0, min(1, (20 * log10(max(rms, 1e-6)) + 50) / 40))
            DispatchQueue.main.async { onLevel?(level) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return .failed(error.localizedDescription)
        }

        generation += 1
        let mine = generation
        latest = ""
        isBusy = true
        self.engine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = result?.isFinal ?? false || error != nil
            DispatchQueue.main.async {
                guard let self, self.generation == mine, self.isBusy else { return }
                if let text, !text.isEmpty {
                    self.latest = text
                    if !done { self.onPartial?(text) }
                }
                if done { self.deliver() }
            }
        }
        return nil
    }

    /// Key released: stop the microphone now, then wait briefly for the recogniser's last word.
    func finish() {
        guard isBusy, engine != nil else { return }
        stopAudio()
        request?.endAudio()
        timeout = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.deliver() }
    }

    func cancel() {
        guard isBusy else { return }
        latest = ""
        stopAudio()
        task?.cancel()
        cleanUp()
    }

    private func deliver() {
        guard isBusy else { return }
        let text = latest
        stopAudio()
        task?.finish()
        cleanUp()
        onFinish?(text)
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func cleanUp() {
        timeout?.invalidate()
        timeout = nil
        request = nil
        task = nil
        isBusy = false
    }
}
