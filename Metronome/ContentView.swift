import SwiftUI

struct ContentView: View {
    @State private var tempo = 120
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 32) {
            Text("Metronome")
                .font(.largeTitle)
                .bold()

            Text("\(tempo) BPM")
                .font(.system(size: 48, weight: .medium, design: .rounded))

            Slider(
                value: Binding(
                    get: { Double(tempo) },
                    set: { tempo = Int($0) }
                ),
                in: 40...240,
                step: 1
            )

            Button(isRunning ? "Stop" : "Start") {
                isRunning.toggle()
            }
            .buttonStyle(.borderedProminent)
            .font(.title2)
        }
        .padding()
    }
}

#Preview {
    ContentView()
} 