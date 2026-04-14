import SwiftUI

// MARK: - Root View (switches between phases)

struct OverlayRootView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch model.phase {
                case .listening:
                    ListeningView(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 1.2)))
                case .transcribing:
                    TranscribingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                case .processing:
                    ProcessingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(width: 500, height: 400)
            .animation(.easeInOut(duration: 0.4), value: model.phase)

            // Partial transcription preview
            if !model.partialText.isEmpty && model.phase == .listening {
                Text(model.partialText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 40)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.3), value: model.partialText)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: ─────────────────────────────────────────────────
// MARK:  Phase 1: LISTENING — Audio-reactive nebula orb
// MARK: ─────────────────────────────────────────────────

struct ListeningView: View {
    @ObservedObject var model: OverlayModel
    @State private var pulse = false
    @State private var spin1 = false
    @State private var spin2 = false
    @State private var breathe = false
    @State private var shimmer = false

    private var level: CGFloat { model.audioLevel }

    // Color shifts with volume: deep blue → electric purple → hot pink
    private var hue: Double { 0.72 - Double(level) * 0.18 }
    private var coreColor: Color {
        Color(hue: hue, saturation: 0.75 + Double(level) * 0.25, brightness: 0.9)
    }
    private var glowColor: Color {
        Color(hue: hue - 0.05, saturation: 0.8, brightness: 0.95)
    }

    var body: some View {
        ZStack {
            // ── Layer 1: Deep space sonar rings ──
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .stroke(
                        coreColor.opacity(0.25),
                        lineWidth: 1.5
                    )
                    .frame(width: 200 + level * 50, height: 200 + level * 50)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0.0 : 0.4)
                    .animation(
                        .easeOut(duration: 2.5)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.4),
                        value: pulse
                    )
            }

            // ── Layer 2: Outer nebula haze ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            coreColor.opacity(0.25 + Double(level) * 0.3),
                            glowColor.opacity(0.1 + Double(level) * 0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .blur(radius: 40)
                .scaleEffect(breathe ? 1.08 : 0.92)

            // ── Layer 3: Counter-rotating gradient halos ──
            haloRing(size: 280 + level * 60, width: 2, speed: 5, clockwise: true,
                     colors: [.clear, coreColor.opacity(0.5), .clear, glowColor.opacity(0.3), .clear])
            haloRing(size: 240 + level * 50, width: 2.5, speed: 7, clockwise: false,
                     colors: [.clear, .cyan.opacity(0.3), .clear, .purple.opacity(0.35), .clear])
            haloRing(size: 200 + level * 40, width: 1.5, speed: 9, clockwise: true,
                     colors: [.clear, .white.opacity(0.15), .clear])

            // ── Layer 4: Inner glow (soft) ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.35),
                            coreColor.opacity(0.7),
                            glowColor.opacity(0.4),
                            .clear
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 110
                    )
                )
                .frame(width: 150 + level * 60, height: 150 + level * 60)
                .blur(radius: 12)

            // ── Layer 5: Sharp core orb ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.95),
                            Color(hue: hue, saturation: 0.6, brightness: 1.0),
                            coreColor,
                            glowColor.opacity(0.5),
                            .clear
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 85
                    )
                )
                .frame(width: 130 + level * 50, height: 130 + level * 50)
                .shadow(color: coreColor.opacity(0.7 + Double(level) * 0.3),
                        radius: 35 + Double(level) * 50)
                .scaleEffect(pulse ? 1.07 : 0.93)

            // ── Layer 6: Spinning accent rings ──
            accentRing(size: 170 + level * 35, width: 3, speed: 3, clockwise: true)
            accentRing(size: 150 + level * 30, width: 2, speed: 4.5, clockwise: false)

            // ── Layer 7: Orbiting particles ──
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10.0 * 360.0
                let radius = 95 + level * 35
                let size = 3 + level * 5
                Circle()
                    .fill(i % 3 == 0 ? Color.white.opacity(0.8) : coreColor.opacity(0.7))
                    .frame(width: size, height: size)
                    .blur(radius: 1)
                    .shadow(color: coreColor.opacity(0.6), radius: 5)
                    .offset(x: radius)
                    .rotationEffect(.degrees(angle + (spin2 ? 360 : 0)))
                    .animation(
                        .linear(duration: 6 + Double(i % 3))
                        .repeatForever(autoreverses: false),
                        value: spin2
                    )
            }

            // ── Layer 8: Central hot spot ──
            Circle()
                .fill(.white)
                .frame(width: 6 + level * 10, height: 6 + level * 10)
                .blur(radius: 2)
                .shadow(color: .white.opacity(0.9), radius: 10 + Double(level) * 8)
                .scaleEffect(shimmer ? 1.3 : 0.7)
        }
        .animation(.easeInOut(duration: 0.1), value: level)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                spin1 = true
            }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                spin2 = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    private func haloRing(size: CGFloat, width: CGFloat, speed: Double,
                           clockwise: Bool, colors: [Color]) -> some View {
        Circle()
            .stroke(
                AngularGradient(gradient: Gradient(colors: colors), center: .center),
                lineWidth: width
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin1 ? (clockwise ? 360 : -360) : 0))
            .animation(.linear(duration: speed).repeatForever(autoreverses: false), value: spin1)
    }

    private func accentRing(size: CGFloat, width: CGFloat, speed: Double,
                             clockwise: Bool) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.6), .clear]),
                    center: .center
                ),
                lineWidth: width
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin1 ? (clockwise ? 360 : -360) : 0))
            .animation(.linear(duration: speed).repeatForever(autoreverses: false), value: spin1)
    }
}

// MARK: ─────────────────────────────────────────────────
// MARK:  Phase 2: TRANSCRIBING — Collapsing energy ring
// MARK: ─────────────────────────────────────────────────

struct TranscribingView: View {
    @State private var spin = false
    @State private var pulse = false
    @State private var dotPulse = false
    @State private var glow = false

    private let accentGold = Color(hue: 0.12, saturation: 0.8, brightness: 1.0)
    private let accentAmber = Color(hue: 0.08, saturation: 0.9, brightness: 0.95)
    private let accentWarm = Color(hue: 0.06, saturation: 0.7, brightness: 1.0)

    var body: some View {
        ZStack {
            // ── Background glow pulse ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentGold.opacity(0.15),
                            accentAmber.opacity(0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 30)
                .scaleEffect(glow ? 1.15 : 0.85)

            // ── Outer spinning arc (wide, faint) ──
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(120))
                .stroke(
                    AngularGradient(
                        colors: [.clear, accentGold.opacity(0.4), accentAmber.opacity(0.6), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: spin)

            // ── Middle spinning arc (counter-rotating) ──
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(90))
                .stroke(
                    AngularGradient(
                        colors: [.clear, accentWarm.opacity(0.5), .white.opacity(0.7), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: spin)

            // ── Inner spinning arc (fast, bright) ──
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(60))
                .stroke(
                    AngularGradient(
                        colors: [.clear, .white.opacity(0.8), accentGold, .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)

            // ── Orbiting dots ──
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6.0 * 360.0
                Circle()
                    .fill(i % 2 == 0 ? accentGold : .white)
                    .frame(width: dotPulse ? 7 : 4, height: dotPulse ? 7 : 4)
                    .shadow(color: accentGold.opacity(0.8), radius: 6)
                    .offset(x: 80)
                    .rotationEffect(.degrees(angle + (spin ? 360 : 0)))
                    .animation(
                        .linear(duration: 3)
                        .repeatForever(autoreverses: false),
                        value: spin
                    )
            }

            // ── Center pulsing core ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, accentGold, accentAmber.opacity(0.5), .clear],
                        center: .center,
                        startRadius: 3,
                        endRadius: 35
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(color: accentGold.opacity(0.8), radius: 20)
                .scaleEffect(pulse ? 1.15 : 0.85)

            // ── "Transcribing" label ──
            Text("Transcribing")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentGold, .white, accentGold],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: accentGold.opacity(0.5), radius: 4)
                .offset(y: 130)
                .opacity(pulse ? 1.0 : 0.6)
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────
// MARK:  Phase 3: PROCESSING — AI enhancement spinner
// MARK: ─────────────────────────────────────────────────

struct ProcessingView: View {
    @State private var spin = false
    @State private var pulse = false
    @State private var glow = false

    private let teal1 = Color(hue: 0.48, saturation: 0.8, brightness: 0.95)
    private let teal2 = Color(hue: 0.52, saturation: 0.7, brightness: 1.0)
    private let cyan = Color(hue: 0.5, saturation: 0.6, brightness: 1.0)

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [teal1.opacity(0.15), teal2.opacity(0.05), .clear],
                        center: .center, startRadius: 30, endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 25)
                .scaleEffect(glow ? 1.1 : 0.9)

            // Outer rotating ring
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(140))
                .stroke(
                    AngularGradient(colors: [.clear, teal1.opacity(0.5), cyan.opacity(0.7), .clear], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: spin)

            // Inner counter-rotating ring
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(100))
                .stroke(
                    AngularGradient(colors: [.clear, .white.opacity(0.7), teal2, .clear], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)

            // Fast inner arc
            ArcShape(startAngle: .degrees(0), endAngle: .degrees(50))
                .stroke(
                    AngularGradient(colors: [.clear, .white.opacity(0.9), teal1, .clear], center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: spin)

            // Center brain icon
            Image(systemName: "brain")
                .font(.system(size: 28))
                .foregroundStyle(
                    LinearGradient(colors: [teal1, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: teal1.opacity(0.6), radius: 8)
                .scaleEffect(pulse ? 1.1 : 0.9)

            // Label
            Text("Enhancing...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [teal1, .white, teal2], startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: teal1.opacity(0.4), radius: 4)
                .offset(y: 120)
                .opacity(pulse ? 1.0 : 0.6)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// MARK: - Arc Shape

struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: startAngle - .degrees(90),
                endAngle: endAngle - .degrees(90),
                clockwise: false
            )
        }
    }
}
