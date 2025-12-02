import SwiftUI

struct CircularCountdownView: View {
    let duration: TimeInterval
    let onComplete: () -> Void

    @State private var timeRemaining: TimeInterval
    @State private var timer: Timer?
    @State private var isComplete = false

    init(duration: TimeInterval = 8.0, onComplete: @escaping () -> Void) {
        self.duration = duration
        self.onComplete = onComplete
        self._timeRemaining = State(initialValue: duration)
    }

    var progress: Double {
        1.0 - (timeRemaining / duration)
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 32, height: 32)

            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            // Countdown number or X
            if isComplete {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(Int(timeRemaining.rounded(.up)))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 0.1
            } else {
                completeCountdown()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func completeCountdown() {
        stopTimer()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isComplete = true
        }
        onComplete()
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        CircularCountdownView {
            print("Countdown complete!")
        }
    }
}