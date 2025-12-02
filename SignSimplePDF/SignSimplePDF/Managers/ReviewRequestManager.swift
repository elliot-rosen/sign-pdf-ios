import Foundation
import StoreKit
import SwiftUI

@MainActor
class ReviewRequestManager: ObservableObject {
    static let shared = ReviewRequestManager()

    // UserDefaults keys
    private let lastRequestDateKey = "lastReviewRequestDate"
    private let requestCountKey = "reviewRequestCount"
    private let documentsProcessedKey = "documentsProcessedCount"
    private let signaturesCreatedKey = "signaturesCreatedCount"
    private let firstLaunchDateKey = "firstLaunchDate"
    private let hasHadErrorRecentlyKey = "hasHadErrorRecently"
    private let successfulActionsKey = "successfulActionsCount"

    // Thresholds
    private let minimumDaysSinceFirstLaunch = 2
    private let minimumDaysBetweenRequests = 30
    private let minimumDocumentsProcessed = 2
    private let minimumSignaturesCreated = 1
    private let minimumSuccessfulActions = 5
    private let maximumRequestsPerYear = 6

    private var lastRequestDate: Date? {
        get { UserDefaults.standard.object(forKey: lastRequestDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRequestDateKey) }
    }

    private var requestCount: Int {
        get { UserDefaults.standard.integer(forKey: requestCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: requestCountKey) }
    }

    private var documentsProcessed: Int {
        get { UserDefaults.standard.integer(forKey: documentsProcessedKey) }
        set { UserDefaults.standard.set(newValue, forKey: documentsProcessedKey) }
    }

    private var signaturesCreated: Int {
        get { UserDefaults.standard.integer(forKey: signaturesCreatedKey) }
        set { UserDefaults.standard.set(newValue, forKey: signaturesCreatedKey) }
    }

    private var firstLaunchDate: Date {
        get {
            if let date = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date {
                return date
            } else {
                let now = Date()
                UserDefaults.standard.set(now, forKey: firstLaunchDateKey)
                return now
            }
        }
    }

    private var hasHadErrorRecently: Bool {
        get { UserDefaults.standard.bool(forKey: hasHadErrorRecentlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasHadErrorRecentlyKey) }
    }

    private var successfulActions: Int {
        get { UserDefaults.standard.integer(forKey: successfulActionsKey) }
        set { UserDefaults.standard.set(newValue, forKey: successfulActionsKey) }
    }

    private init() {
        // Initialize first launch date if needed
        _ = firstLaunchDate
    }

    // MARK: - Public Methods

    /// Call when a document is successfully processed (opened, signed, edited)
    func recordDocumentProcessed() {
        documentsProcessed += 1
        recordSuccessfulAction()

        // Check if we should request after processing 3rd, 5th, or 10th document
        if [2, 3, 5, 10].contains(documentsProcessed) {
            requestReviewIfAppropriate()
        }
    }

    /// Call when a signature is successfully created and saved
    func recordSignatureCreated() {
        signaturesCreated += 1
        recordSuccessfulAction()

        // Request after 2nd signature
        if [1, 3].contains(signaturesCreated) {
            requestReviewIfAppropriate()
        }
    }

    /// Call when a PDF is successfully exported or shared
    func recordPDFExported() {
        recordSuccessfulAction()

        // Check after every 5th successful export
        if successfulActions % 3 == 0 && successfulActions >= 3 {
            requestReviewIfAppropriate()
        }
    }

    /// Call when user successfully uses a premium feature
    func recordPremiumFeatureUsed() {
        recordSuccessfulAction()

        // Premium users who use features successfully are good candidates
        if successfulActions >= 2 {
            requestReviewIfAppropriate()
        }
    }

    /// Call when a successful action occurs
    private func recordSuccessfulAction() {
        successfulActions += 1
        // Clear any recent error flags after successful actions
        if successfulActions % 3 == 0 {
            hasHadErrorRecently = false
        }
    }

    /// Call when an error occurs
    func recordError() {
        hasHadErrorRecently = true
    }

    // MARK: - Review Request Logic

    func requestReviewIfAppropriate() {
        guard shouldRequestReview() else { return }

        // Delay slightly to not interrupt user flow
        requestReview()
    }

    private func shouldRequestReview() -> Bool {
        // Don't request if there was a recent error
        if hasHadErrorRecently {
            print("Review Request: Skipped due to recent error")
            return false
        }

        // Check if enough time has passed since first launch
        let daysSinceFirstLaunch = Calendar.current.dateComponents([.day],
                                                                  from: firstLaunchDate,
                                                                  to: Date()).day ?? 0
        if requestCount == 0 {
            // allow first request as soon as minimum engagement is met
        } else if daysSinceFirstLaunch < minimumDaysSinceFirstLaunch {
            print("Review Request: Too soon since first launch (\(daysSinceFirstLaunch) days)")
            return false
        }

        // Check if enough time has passed since last request
        if let lastRequest = lastRequestDate {
            let daysSinceLastRequest = Calendar.current.dateComponents([.day],
                                                                      from: lastRequest,
                                                                      to: Date()).day ?? 0
            if daysSinceLastRequest < minimumDaysBetweenRequests {
                print("Review Request: Too soon since last request (\(daysSinceLastRequest) days)")
                return false
            }
        }

        // Check if we've exceeded maximum requests this year
        if let lastRequest = lastRequestDate {
            let yearOfLastRequest = Calendar.current.component(.year, from: lastRequest)
            let currentYear = Calendar.current.component(.year, from: Date())

            if yearOfLastRequest == currentYear && requestCount >= maximumRequestsPerYear {
                print("Review Request: Maximum requests reached this year")
                return false
            }
        }

        // Check minimum engagement thresholds
        let hasMinimumEngagement = documentsProcessed >= minimumDocumentsProcessed ||
                                  signaturesCreated >= minimumSignaturesCreated ||
                                  successfulActions >= minimumSuccessfulActions

        if !hasMinimumEngagement {
            print("Review Request: Insufficient engagement (docs: \(documentsProcessed), sigs: \(signaturesCreated), actions: \(successfulActions))")
            return false
        }

        print("Review Request: All conditions met, will request review")
        return true
    }

    private func requestReview() {
        // Update tracking
        lastRequestDate = Date()
        requestCount += 1

        // Request review using the scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            print("Review Request: Presented to user")
        }
    }

    // MARK: - Debug Methods (for testing)

    #if DEBUG
    func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: lastRequestDateKey)
        UserDefaults.standard.removeObject(forKey: requestCountKey)
        UserDefaults.standard.removeObject(forKey: documentsProcessedKey)
        UserDefaults.standard.removeObject(forKey: signaturesCreatedKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchDateKey)
        UserDefaults.standard.removeObject(forKey: hasHadErrorRecentlyKey)
        UserDefaults.standard.removeObject(forKey: successfulActionsKey)
    }

    func forceShowReview() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }
    #endif
}

// MARK: - View Modifier for Easy Integration

struct ReviewRequestModifier: ViewModifier {
    let trigger: ReviewTrigger

    enum ReviewTrigger {
        case documentSaved
        case signatureCreated
        case pdfExported
        case premiumFeatureUsed
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task {
                    await handleTrigger()
                }
            }
    }

    @MainActor
    private func handleTrigger() async {
        switch trigger {
        case .documentSaved:
            ReviewRequestManager.shared.recordDocumentProcessed()
        case .signatureCreated:
            ReviewRequestManager.shared.recordSignatureCreated()
        case .pdfExported:
            ReviewRequestManager.shared.recordPDFExported()
        case .premiumFeatureUsed:
            ReviewRequestManager.shared.recordPremiumFeatureUsed()
        }
    }
}

extension View {
    func requestReviewAfter(_ trigger: ReviewRequestModifier.ReviewTrigger) -> some View {
        modifier(ReviewRequestModifier(trigger: trigger))
    }
}
