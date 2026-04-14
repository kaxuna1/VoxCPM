import SwiftUI

struct ListeningOverlayView: View {
    @ObservedObject var model: AudioLevelModel
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            OrbRing(delay: 0.0, audioLevel: model.audioLevel, pulse: pulse)
            OrbRing(delay: 0.6, audioLevel: model.audioLevel, pulse: pulse)
            OrbRing(delay: 1.2, audioLevel: model.audioLevel, pulse: pulse)

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.9),
                            Color.blue.opacity(0.7),
                            Color.indigo.opacity(0.5),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 120
                    )
                )
                .frame(width: 160 + (model.audioLevel * 60), height: 160 + (model.audioLevel * 60))
                .shadow(color: Color.purple.opacity(0.5 + Double(model.audioLevel) * 0.4), radius: 40 + Double(model.audioLevel) * 30, x: 0, y: 0)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

            // Inner spinning accent
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, .white.opacity(0.6), .clear]),
                        center: .center
                    ),
                    lineWidth: 4
                )
                .frame(width: 180 + (model.audioLevel * 40), height: 180 + (model.audioLevel * 40))
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: rotate)
        }
        .frame(width: 400, height: 400)
        .onAppear {
            pulse.toggle()
            rotate.toggle()
        }
    }
}

struct OrbRing: View {
    let delay: Double
    let audioLevel: CGFloat
    let pulse: Bool

    var body: some View {
        Circle()
            .stroke(Color.purple.opacity(0.3), lineWidth: 2)
            .frame(width: 220 + (audioLevel * 80), height: 220 + (audioLevel * 80))
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.0 : 0.6)
            .animation(
                .easeOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(delay),
                value: pulse
            )
    }
}
