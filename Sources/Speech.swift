import AVFoundation
import Speech

/// Doimiy mikrofon tinglovchi: bir necha soniyalik "segment"larga bo'lib nutqni aniqlaydi.
final class SpeechListener {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var generation = 0
    private var active = false
    private var onDevice = false
    private var recycleTimer: Timer?
    private var errorStreak = 0

    var onPartial: ((String) -> Void)?
    var onFatal: ((String) -> Void)?

    var isRunning: Bool { active }

    func start(recognizer: SFSpeechRecognizer, onDevice: Bool, recycle: Bool) throws {
        stop()
        self.recognizer = recognizer
        self.onDevice = onDevice
        errorStreak = 0

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let req = self.request
            self.lock.unlock()
            req?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        active = true
        beginSegment()

        if recycle {
            recycleTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: true) { [weak self] _ in
                self?.beginSegment()
            }
        }
    }

    func stop() {
        active = false
        recycleTimer?.invalidate()
        recycleTimer = nil
        lock.lock()
        generation += 1
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        lock.unlock()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func beginSegment() {
        guard active, let recognizer else { return }
        lock.lock()
        request?.endAudio()
        task?.cancel()
        generation += 1
        let gen = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = onDevice
        req.addsPunctuation = false
        request = req
        lock.unlock()

        let t = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            self.lock.lock()
            let current = (gen == self.generation)
            self.lock.unlock()
            guard current else { return }
            if let result {
                self.errorStreak = 0
                self.onPartial?(result.bestTranscription.formattedString)
                if result.isFinal { self.restartSoon() }
            }
            if error != nil { self.restartSoon() }
        }
        lock.lock()
        task = t
        lock.unlock()
    }

    private func restartSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.active else { return }
            self.errorStreak += 1
            if self.errorStreak > 12 {
                self.onFatal?("Nutq aniqlash ishlamayapti (internet yoki til paketi kerak bo'lishi mumkin).")
                return
            }
            self.beginSegment()
        }
    }
}

enum RecognizerFactory {
    /// Til tanlash: avval o'zbekcha, bo'lmasa ruscha/turkcha/inglizcha. Offline (qurilma ichida) ishlaydiganiga ustunlik.
    static func make(pref: String) -> (recognizer: SFSpeechRecognizer, onDevice: Bool, id: String)? {
        let candidates = pref == "auto" ? ["uz-UZ", "ru-RU", "tr-TR", "en-US"] : [pref]
        var fallback: (SFSpeechRecognizer, String)?
        for id in candidates {
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable else { continue }
            if r.supportsOnDeviceRecognition { return (r, true, id) }
            if fallback == nil { fallback = (r, id) }
        }
        if let f = fallback { return (f.0, false, f.1) }
        return nil
    }

    static func describe(pref: String) -> String {
        guard let m = make(pref: pref) else { return "Mos nutq aniqlagich topilmadi." }
        return m.onDevice
            ? "Til: \(m.id) — internetsiz ishlaydi."
            : "Til: \(m.id) — bu til telefonda yuklanmagan, internet kerak bo'ladi. Sozlamalar → Umumiy → Klaviatura → Diktovka tillari orqali tilni qo'shing."
    }
}

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var cont: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    static func pickVoice() -> (voice: AVSpeechSynthesisVoice?, translit: Bool) {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let uz = voices.filter({ $0.language.hasPrefix("uz") }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return (uz, false)
        }
        if let tr = voices.filter({ $0.language.hasPrefix("tr") }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return (tr, true)
        }
        return (AVSpeechSynthesisVoice(language: "en-US"), false)
    }

    static func describeVoice() -> String {
        let v = pickVoice()
        guard let voice = v.voice else { return "Ovoz topilmadi." }
        return v.translit
            ? "Ovoz: \(voice.name) (turkcha ovoz o'zbekcha matnni o'qiydi)."
            : "Ovoz: \(voice.name) (\(voice.language))."
    }

    func speak(_ raw: String) async {
        stop()
        let pick = Self.pickVoice()
        var text = UzbekTranslit.clean(raw)
        if pick.translit { text = UzbekTranslit.toTurkish(text) }
        guard !text.isEmpty else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)

        let u = AVSpeechUtterance(string: text)
        u.voice = pick.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.cont = c
            self.synth.speak(u)
        }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        resume()
    }

    private func resume() {
        let c = cont
        cont = nil
        c?.resume()
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
