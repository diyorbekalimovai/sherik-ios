import SwiftUI

private let gold = Color(red: 0.93, green: 0.74, blue: 0.28)
private let turquoise = Color(red: 0.12, green: 0.75, blue: 0.78)

struct ContentView: View {
    @EnvironmentObject var a: Assistant
    @Environment(\.scenePhase) private var scenePhase
    @State private var input = ""
    @State private var showSettings = false

    var body: some View {
        ZStack {
            BackgroundView()
            VStack(spacing: 0) {
                header
                ModelBanner(llm: a.llm)
                if let n = a.notice {
                    Text(n)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.35))
                        .onTapGesture { a.notice = nil }
                }
                chat
                controls
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(a)
        }
        .task { await a.bootstrap() }
        .onChange(of: scenePhase) { _, new in a.scenePhaseChanged(new) }
    }

    private var header: some View {
        HStack {
            Text("SHERIK")
                .font(.system(size: 22, weight: .heavy, design: .serif))
                .tracking(6)
                .foregroundStyle(gold)
            Spacer()
            Circle()
                .fill(a.net.isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(a.net.isOnline ? "internet bor" : "internetsiz")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.8))
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if a.messages.isEmpty {
                        Text("“Hey Sherik” deng yoki pastdagi doirani bosing.")
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 40)
                    }
                    ForEach(a.messages) { m in
                        Bubble(message: m).id(m.id)
                    }
                    if !a.partial.isEmpty {
                        Bubble(message: .init(role: .user, text: a.partial)).opacity(0.6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: a.messages.count) { _, _ in
                if let last = a.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if a.pendingQuestion != nil {
                HStack(spacing: 12) {
                    Button { Task { await a.consentAnswered(true) } } label: {
                        Label("Ha, internetdan izla", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(turquoise)
                    Button { Task { await a.consentAnswered(false) } } label: {
                        Text("Yo'q").frame(width: 70)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.horizontal, 16)
            }
            OrbView(phase: a.phase)
                .onTapGesture { a.orbTapped() }
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            HStack {
                TextField("Yoki yozing…", text: $input)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(gold)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .padding(.top, 6)
        .background(.black.opacity(0.25))
    }

    private func send() {
        let t = input
        input = ""
        a.sendText(t)
    }

    private var statusText: String {
        switch a.phase {
        case .idle: return "Doirani bosing"
        case .wake: return "“Hey Sherik” deng…"
        case .command: return "Tinglayapman…"
        case .consent: return "Ha yoki yo'q deng…"
        case .thinking: return "O'ylayapman…"
        case .speaking: return "Gapiryapman…"
        }
    }
}

struct Bubble: View {
    let message: Assistant.Message
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .foregroundStyle(.white)
                if message.viaCloud {
                    Label("internet orqali", systemImage: "globe")
                        .font(.caption2)
                        .foregroundStyle(turquoise)
                }
            }
            .padding(12)
            .background(
                message.role == .user ? Color.white.opacity(0.14) : turquoise.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 16))
            if message.role == .sherik { Spacer(minLength: 40) }
        }
    }
}

struct ModelBanner: View {
    @ObservedObject var llm: LocalLLM
    var body: some View {
        switch llm.state {
        case .downloading:
            VStack(spacing: 4) {
                Text("Offline miya yuklanmoqda (bir marta, internet kerak): \(Int(llm.progress * 100))%")
                    .font(.caption)
                ProgressView(value: llm.progress).tint(gold)
            }
            .padding(10)
            .background(.black.opacity(0.3))
            .foregroundStyle(.white)
        case .failed(let e):
            VStack(spacing: 6) {
                Text("Offline miya yuklanmadi: \(e)").font(.caption)
                Button("Qayta urinish") { Task { await llm.load() } }
                    .buttonStyle(.bordered).tint(gold)
            }
            .padding(10)
            .foregroundStyle(.white)
            .background(Color.red.opacity(0.3))
        default:
            EmptyView()
        }
    }
}

struct OrbView: View {
    let phase: Assistant.Phase
    @State private var pulse = false

    private var colors: [Color] {
        switch phase {
        case .idle: return [.gray, Color(white: 0.25)]
        case .wake: return [turquoise, Color(red: 0.0, green: 0.3, blue: 0.5)]
        case .command, .consent: return [gold, Color(red: 0.7, green: 0.35, blue: 0.0)]
        case .thinking: return [.purple, .indigo]
        case .speaking: return [.green, turquoise]
        }
    }

    private var icon: String {
        switch phase {
        case .idle: return "mic.slash.fill"
        case .wake: return "ear.fill"
        case .command, .consent: return "mic.fill"
        case .thinking: return "brain"
        case .speaking: return "waveform"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: colors, center: .center, startRadius: 4, endRadius: 70))
                .frame(width: 112, height: 112)
                .scaleEffect(pulse ? 1.07 : 0.96)
                .shadow(color: colors[0].opacity(0.6), radius: pulse ? 26 : 10)
            Circle().stroke(gold.opacity(0.8), lineWidth: 2).frame(width: 126, height: 126)
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct BackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.07, blue: 0.20), Color(red: 0.0, green: 0.22, blue: 0.32)],
                startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let step: CGFloat = 48
                var y: CGFloat = 0
                while y < size.height + step {
                    var x: CGFloat = 0
                    while x < size.width + step {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y - 14))
                        p.addLine(to: CGPoint(x: x + 14, y: y))
                        p.addLine(to: CGPoint(x: x, y: y + 14))
                        p.addLine(to: CGPoint(x: x - 14, y: y))
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(gold.opacity(0.07)), lineWidth: 1)
                        x += step
                    }
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}
