import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Telefonning o'zida (internetsiz) ishlaydigan kichik til modeli.
@MainActor
final class LocalLLM: ObservableObject {
    enum State: Equatable {
        case notLoaded, downloading, ready
        case failed(String)
    }

    enum LLMError: Error { case notReady }

    @Published var state: State = .notLoaded
    @Published var progress: Double = 0

    private var container: ModelContainer?
    private var session: ChatSession?
    private var turns = 0

    static let configuration = LLMRegistry.gemma3_1B_qat_4bit

    var isReady: Bool { state == .ready }

    func load() async {
        switch state {
        case .downloading, .ready: return
        default: break
        }
        state = .downloading
        progress = 0
        do {
            let c = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: Self.configuration,
                progressHandler: { [weak self] p in
                    let f = p.fractionCompleted
                    Task { @MainActor in self?.progress = f }
                })
            container = c
            makeSession()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func makeSession() {
        guard let container else { return }
        session = ChatSession(
            container,
            instructions: Persona.localSystem,
            generateParameters: GenerateParameters(maxTokens: 350, temperature: 0.6))
        turns = 0
    }

    func resetConversation() { makeSession() }

    func respond(to prompt: String, onUpdate: @escaping (String) -> Void) async throws -> String {
        if turns >= 10 { makeSession() }
        guard let session else { throw LLMError.notReady }
        turns += 1
        var out = ""
        for try await chunk in session.streamResponse(to: prompt) {
            out += chunk
            onUpdate(out)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
