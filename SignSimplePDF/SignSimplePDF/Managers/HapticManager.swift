import UIKit

class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // Impact feedback for various actions
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    // Selection feedback for picker-type controls
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // Notification feedback for success/error states
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    // Convenience methods
    func success() {
        notification(.success)
    }

    func error() {
        notification(.error)
    }

    func warning() {
        notification(.warning)
    }

    // Button tap feedback
    func buttonTap() {
        impact(.light)
    }

    // Important action feedback
    func importantAction() {
        impact(.heavy)
    }

    // Subtle feedback for UI transitions
    func subtle() {
        impact(.light)
    }
}