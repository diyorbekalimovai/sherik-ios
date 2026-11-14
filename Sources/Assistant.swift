import AVFoundation
import Speech
import SwiftUI
import UIKit

@MainActor
final class Assistant: ObservableObject {
    static let shared = Assistant()

    enum Phase { case idle, wake, command, thinking, speaking, consent }

    struct Message: Identifiable {
        enum Role { case user, sherik }
        let id = UUID()
        let role: Role
        var text: String
        var viaCloud = false
    }

    @Published var phase: Phase = .idle
    @Published var messages: [Message] = []
    @Published var partial = ""
    @Published var notice: String?
    @Published var pendingQuestion: String?
    @Published var sttInfo = ""

    let settings = AppSettings.shared
    let llm = LocalLLM()
    let net = NetworkMonitor()

    private let listener = SpeechListener()
    private let speaker = Speaker()
    private var deadlineTask: Task<Void, Never>?
    private var isForeground = true
    private var started = false
    private var activationRequested = false

    init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                guard let self, self.phase == .wake || self.phase == .idle, self.started else { return }
                self.returnToWake()
            }
        }
    }

    // MARK: - Ishga tushirish

    func bootstrap() async {
        guard !started else { return }
        started = true
        refreshInfo()
        let ok = await requestPermissions()
        guard ok else {
            notice = "Mikrofon va nutq aniqlashga ruxsat kerak (Sozlamalar → Sherik)."
            phase = .idle
            return
        }
        Task { await llm.load() }
        if activationRequested {
            activationRequested = false
            await manualActivate()
        } else {
            returnToWake()
        }
    }

    func refreshInfo() {
        sttInfo = RecognizerFactory.describe(pref: settings.localeID) + " " + Speaker.describeVoice()
    }

    private func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        return speechOK && micOK
    }

    func scenePhaseChanged(_ p: ScenePhase) {
        isForeground = (p == .active)
        updateIdleTimer()
        if p == .active {
            if activationRequested && started {
                activationRequested = false
                Task { await manualActivate() }
            } else if started && phase == .idle {
                returnToWake()
            }
        }
    }

    /// Siri/Shortcuts orqali ("Hey Siri, Sherik") chaqirilganda.
    func requestActivation() {
        activationRequested = true
        if started && isForeground {
            activationRequested = false
            Task { await manualActivate() }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && isForeground && phase != .idle
    }

    // MARK: - Tinglash

    func returnToWake() {
        deadlineTask?.cancel()
        listener.stop()
        partial = ""
        guard settings.wakeEnabled else { phase = .idle; updateIdleTimer(); return }
        guard let m = RecognizerFactory.make(pref: settings.localeID) else {
            notice = "Nutq aniqlagich topilmadi."
            phase = .idle
            return
        }
        listener.onPartial = { [weak self] text in
            Task { @MainActor in self?.heard(text) }
        }
        listener.onFatal = { [weak self] msg in
            Task { @MainActor in
                self?.notice = msg
                self?.phase = .idle
            }
        }
        do {
            try listener.start(recognizer: m.recognizer, onDevice: m.onDevice, recycle: true)
            phase = .wake
        } catch {
            notice = "Mikrofonni ochib bo'lmadi: \(error.localizedDescription)"
            phase = .idle
        }
        updateIdleTimer()
    }

    func restartListening() {
        refreshInfo()
        guard started else { return }
        if phase == .wake || phase == .idle { returnToWake() }
    }

    private func startCommand(timeout: Double, consent: Bool = false) {
        deadlineTask?.cancel()
        listener.stop()
        partial = ""
        guard let m = RecognizerFactory.make(pref: settings.localeID) else { returnToWake(); return }
        listener.onPartial = { [weak self] text in
            Task { @MainActor in self?.heard(text) }
        }
        listener.onFatal = { [weak self] msg in
            Task { @MainActor in self?.notice = msg; self?.returnToWake() }
        }
        do {
            try listener.start(recognizer: m.recognizer, onDevice: m.onDevice, recycle: false)
        } catch {
            notice = "Mikrofonni ochib bo'lmadi: \(error.localizedDescription)"
            phase = .idle
            return
        }
        phase = consent ? .consent : .command
        updateIdleTimer()
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.timedOut()
        }
    }

    private func heard(_ text: String) {
        switch phase {
        case .wake:
            partial = ""
            if WakeWord.matches(text) {
                phase = .speaking
                Task { await wakeTriggered() }
            }
        case .command, .consent:
            partial = text
            deadlineTask?.cancel()
            deadlineTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                await self?.finalizeCommand()
            }
        default:
            break
        }
    }

    private func wakeTriggered() async {
        listener.stop()
        await say("Eshitaman, janob.")
        startCommand(timeout: 8)
    }

    private func manualActivate() async {
        listener.stop()
        deadlineTask?.cancel()
        speaker.stop()
        await say("Eshitaman, janob.")
        startCommand(timeout: 8)
    }

    private func timedOut() async {
        listener.stop()
        if phase == .consent {
            pendingQuestion = nil
            await say("Xo'p, janob, internetga chiqmayman.")
        }
        returnToWake()
    }

    private func finalizeCommand() async {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasConsent = (phase == .consent)
        listener.stop()
        partial = ""
        if wasConsent {
            if let yes = YesNo.parse(text) {
                await consentAnswered(yes)
            } else {
                await say("Tushunmadim, janob. Ha yoki yo'q deng.")
                startCommand(timeout: 8, consent: true)
            }
        } else {
            await process(text)
        }
    }

    // MARK: - Savolga javob

    func orbTapped() {
        switch phase {
        case .idle:
            Task { await bootstrapOrStart() }
        case .wake:
            Task { await manualActivate() }
        case .command, .consent:
            returnToWake()
        case .speaking:
            speaker.stop()
        case .thinking:
            break
        }
    }

    private func bootstrapOrStart() async {
        if !started { await bootstrap() } else { await manualActivate() }
    }

    func sendText(_ t: String) {
        let text = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        deadlineTask?.cancel()
        listener.stop()
        speaker.stop()
        Task { await process(text) }
    }

    private func process(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { returnToWake(); return }
        messages.append(Message(role: .user, text: text))
        phase = .thinking
        let lower = text.lowercased()
        if lower.contains("internetdan") || lower.contains("internet orqali") {
            await askCloud(text)
            return
        }
        if !isForeground || Self.needsCloud(text) {
            await requestConsent(text)
            return
        }
        await answerLocally(text)
    }

    private func answerLocally(_ text: String) async {
        guard llm.isReady else {
            if !settings.apiKey.isEmpty && net.isOnline {
                await requestConsent(text)
            } else {
                let why: String
                switch llm.state {
                case .downloading: why = "Model hali yuklanmoqda, janob. Biroz kuting."
                case .failed: why = "Model yuklanmagan, janob. Bir marta internet orqali yuklab olish kerak."
                default: why = "Model hali tayyor emas, janob."
                }
                messages.append(Message(role: .sherik, text: why))
                await say(why)
                followUp()
            }
            return
        }
        messages.append(Message(role: .sherik, text: "…"))
        let idx = messages.count - 1
        do {
            let reply = try await llm.respond(to: text) { [weak self] partial in
                guard let self, idx < self.messages.count else { return }
                if !partial.contains("[") { self.messages[idx].text = partial }
            }
            if reply.contains("[INTERNET]") {
                messages.removeLast()
                await requestConsent(text)
                return
            }
            messages[idx].text = reply
            await say(reply)
            followUp()
        } catch {
            messages[idx].text = "Xatolik: \(error.localizedDescription)"
            await say("Kechirasiz, janob, xatolik yuz berdi.")
            followUp()
        }
    }

    private func requestConsent(_ text: String) async {
        pendingQuestion = text
        if settings.apiKey.isEmpty {
            pendingQuestion = nil
            let m = "Bu savol uchun internet kerak, janob, lekin sozlamalarda internet kaliti kiritilmagan."
            messages.append(Message(role: .sherik, text: m))
            await say(m)
            followUp()
            return
        }
        if settings.autoCloud {
            pendingQuestion = nil
            await askCloud(text)
            return
        }
        phase = .speaking
        await say("Bu savol og'irroq, janob. Internet orqali javob izlaymi?")
        guard pendingQuestion != nil else { return }
        startCommand(timeout: 9, consent: true)
    }

    /// Tugma yoki ovoz orqali "ha / yo'q".
    func consentAnswered(_ yes: Bool) async {
        deadlineTask?.cancel()
        listener.stop()
        speaker.stop()
        guard let q = pendingQuestion else { returnToWake(); return }
        pendingQuestion = nil
        if yes {
            await askCloud(q)
        } else {
            let m = "Xo'p, janob."
            await say(m)
            returnToWake()
        }
    }

    private func askCloud(_ text: String) async {
        phase = .thinking
        guard net.isOnline else {
            let m = "Internet o'chiq, janob. Iltimos, Wi-Fi yoki mobil internetni yoqing va savolni qayta bering."
            notice = "Internet o'chiq — yoqing va qayta urinib ko'ring."
            messages.append(Message(role: .sherik, text: m))
            await say(m)
            followUp()
            return
        }
        do {
            let reply = try await CloudClient.ask(
                messages: cloudMessages(),
                apiKey: settings.apiKey,
                model: settings.cloudModel,
                webSearch: settings.useWebSearch)
            messages.append(Message(role: .sherik, text: reply, viaCloud: true))
            await say(reply)
        } catch {
            let m = "Internet orqali ulanib bo'lmadi, janob."
            notice = error.localizedDescription
            messages.append(Message(role: .sherik, text: m))
            await say(m)
        }
        followUp()
    }

    private func cloudMessages() -> [(role: String, text: String)] {
        var out: [(role: String, text: String)] = []
        for m in messages.suffix(12) {
            let role = (m.role == .user) ? "user" : "assistant"
            if m.text == "…" { continue }
            if let last = out.last, last.role == role {
                out[out.count - 1].text += "\n" + m.text
            } else {
                out.append((role, m.text))
            }
        }
        while let first = out.first, first.role != "user" { out.removeFirst() }
        return out
    }

    private func say(_ text: String) async {
        phase = .speaking
        await speaker.speak(text)
    }

    private func followUp() {
        if settings.wakeEnabled || phase != .idle {
            startCommand(timeout: 6)
        } else {
            phase = .idle
        }
    }

    func clearConversation() {
        messages.removeAll()
        llm.resetConversation()
    }

    static func needsCloud(_ q: String) -> Bool {
        let t = q.lowercased()
        if t.count > 160 { return true }
        let keys = [
            "internet", "yangilik", "bugun", "hozir", "ob-havo", "ob havo", "havo qanday", "kurs", "dollar",
            "narx", "tarjima", "yozib ber", "maqola", "insho", "kod yoz", "dastur yoz", "tahlil", "hisobla",
            "qidir", "google", "natija", "kim yutdi", "oxirgi", "so'nggi", "prezident",
        ]
        return keys.contains { t.contains($0) }
    }
}
