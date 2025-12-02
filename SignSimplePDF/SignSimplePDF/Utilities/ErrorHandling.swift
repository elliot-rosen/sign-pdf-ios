import Foundation
import SwiftUI

// MARK: - App Error Types

enum AppError: LocalizedError, Identifiable {

    // Document Errors
    case documentNotFound
    case documentCorrupted
    case documentImportFailed(reason: String)
    case documentExportFailed(reason: String)
    case documentSaveFailed
    case documentDeleteFailed
    case documentTooLarge(maxSize: Int)
    case unsupportedFileFormat

    // Signature Errors
    case signatureCreationFailed
    case signatureSaveFailed
    case signatureDeleteFailed
    case signatureLimitReached
    case signatureNotFound

    // PDF Processing Errors
    case pdfProcessingFailed(reason: String)
    case pdfPageNotFound
    case pdfAnnotationFailed
    case pdfRenderingFailed
    case insufficientMemory

    // Core Data Errors
    case dataStorageError(reason: String)
    case dataFetchError
    case dataMigrationFailed

    // Subscription Errors
    case subscriptionLoadFailed
    case purchaseFailed(reason: String)
    case purchaseCancelled
    case purchasePending
    case restorationFailed
    case subscriptionExpired
    case networkUnavailable

    // Permission Errors
    case cameraPermissionDenied
    case photoLibraryPermissionDenied
    case fileAccessDenied

    // General Errors
    case unknown
    case invalidOperation

    // Identifiable conformance
    var id: String {
        switch self {
        case .documentNotFound:
            return "documentNotFound"
        case .documentCorrupted:
            return "documentCorrupted"
        case .documentImportFailed(let reason):
            return "documentImportFailed_\(reason)"
        case .documentExportFailed(let reason):
            return "documentExportFailed_\(reason)"
        case .documentSaveFailed:
            return "documentSaveFailed"
        case .documentDeleteFailed:
            return "documentDeleteFailed"
        case .documentTooLarge(let maxSize):
            return "documentTooLarge_\(maxSize)"
        case .unsupportedFileFormat:
            return "unsupportedFileFormat"
        case .signatureCreationFailed:
            return "signatureCreationFailed"
        case .signatureSaveFailed:
            return "signatureSaveFailed"
        case .signatureDeleteFailed:
            return "signatureDeleteFailed"
        case .signatureLimitReached:
            return "signatureLimitReached"
        case .signatureNotFound:
            return "signatureNotFound"
        case .pdfProcessingFailed(let reason):
            return "pdfProcessingFailed_\(reason)"
        case .pdfPageNotFound:
            return "pdfPageNotFound"
        case .pdfAnnotationFailed:
            return "pdfAnnotationFailed"
        case .pdfRenderingFailed:
            return "pdfRenderingFailed"
        case .insufficientMemory:
            return "insufficientMemory"
        case .dataStorageError(let reason):
            return "dataStorageError_\(reason)"
        case .dataFetchError:
            return "dataFetchError"
        case .dataMigrationFailed:
            return "dataMigrationFailed"
        case .subscriptionLoadFailed:
            return "subscriptionLoadFailed"
        case .purchaseFailed(let reason):
            return "purchaseFailed_\(reason)"
        case .purchaseCancelled:
            return "purchaseCancelled"
        case .purchasePending:
            return "purchasePending"
        case .restorationFailed:
            return "restorationFailed"
        case .subscriptionExpired:
            return "subscriptionExpired"
        case .networkUnavailable:
            return "networkUnavailable"
        case .cameraPermissionDenied:
            return "cameraPermissionDenied"
        case .photoLibraryPermissionDenied:
            return "photoLibraryPermissionDenied"
        case .fileAccessDenied:
            return "fileAccessDenied"
        case .unknown:
            return "unknown"
        case .invalidOperation:
            return "invalidOperation"
        }
    }

    var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "The document could not be found."
        case .documentCorrupted:
            return "The document appears to be corrupted and cannot be opened."
        case .documentImportFailed(let reason):
            return "Failed to import document: \(reason)"
        case .documentExportFailed(let reason):
            return "Failed to export document: \(reason)"
        case .documentSaveFailed:
            return "Failed to save the document. Please try again."
        case .documentDeleteFailed:
            return "Failed to delete the document."
        case .documentTooLarge(let maxSize):
            return "Document exceeds maximum size of \(maxSize / 1024 / 1024)MB."
        case .unsupportedFileFormat:
            return "This file format is not supported. Please use PDF files."

        case .signatureCreationFailed:
            return "Failed to create signature. Please try again."
        case .signatureSaveFailed:
            return "Failed to save signature."
        case .signatureDeleteFailed:
            return "Failed to delete signature."
        case .signatureLimitReached:
            return "You've reached the maximum number of signatures. Upgrade to Premium for unlimited signatures."
        case .signatureNotFound:
            return "The selected signature could not be found."

        case .pdfProcessingFailed(let reason):
            return "PDF processing failed: \(reason)"
        case .pdfPageNotFound:
            return "The requested page could not be found in the PDF."
        case .pdfAnnotationFailed:
            return "Failed to add annotation to PDF."
        case .pdfRenderingFailed:
            return "Failed to render PDF. The file may be corrupted."
        case .insufficientMemory:
            return "Not enough memory to process this document. Try closing other apps."

        case .dataStorageError(let reason):
            return "Data storage error: \(reason)"
        case .dataFetchError:
            return "Failed to retrieve data."
        case .dataMigrationFailed:
            return "Failed to migrate data. Please reinstall the app."

        case .subscriptionLoadFailed:
            return "Failed to load subscription information."
        case .purchaseFailed(let reason):
            return "Purchase failed: \(reason)"
        case .purchaseCancelled:
            return "Purchase was cancelled."
        case .purchasePending:
            return "Purchase is pending approval."
        case .restorationFailed:
            return "Failed to restore purchases."
        case .subscriptionExpired:
            return "Your subscription has expired. Renew to continue using premium features."
        case .networkUnavailable:
            return "Network connection unavailable. Please check your internet connection."

        case .cameraPermissionDenied:
            return "Camera access denied. Enable in Settings to scan documents."
        case .photoLibraryPermissionDenied:
            return "Photo library access denied. Enable in Settings to import images."
        case .fileAccessDenied:
            return "File access denied. Please check permissions."

        case .unknown:
            return "An unknown error occurred."
        case .invalidOperation:
            return "This operation is not valid."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .documentTooLarge:
            return "Try compressing the PDF or splitting it into smaller documents."
        case .insufficientMemory:
            return "Close other apps and try again. If the problem persists, restart your device."
        case .signatureLimitReached:
            return "Upgrade to Premium to save unlimited signatures."
        case .networkUnavailable:
            return "Check your Wi-Fi or cellular connection and try again."
        case .cameraPermissionDenied, .photoLibraryPermissionDenied:
            return "Go to Settings > SignSimple PDF and enable the required permissions."
        case .subscriptionExpired:
            return "Tap here to renew your subscription."
        default:
            return nil
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .purchaseCancelled, .networkUnavailable,
             .cameraPermissionDenied, .photoLibraryPermissionDenied,
             .signatureLimitReached, .subscriptionExpired:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Alert View Modifier

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .alert(item: $error) { error in
                Alert(
                    title: Text("Error"),
                    message: Text(error.errorDescription ?? "An error occurred"),
                    primaryButton: .default(Text("OK")) {
                        onDismiss?()
                    },
                    secondaryButton: error.recoverySuggestion != nil
                        ? .cancel(Text("Help"))
                        : .cancel()
                )
            }
    }
}

extension View {
    func errorAlert(_ error: Binding<AppError?>, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(error: error, onDismiss: onDismiss))
    }
}

// MARK: - Error Logger

class ErrorLogger {
    static let shared = ErrorLogger()

    private init() {}

    func log(_ error: AppError, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        #if DEBUG
        print("❌ ERROR in \(fileName):\(line) - \(function)")
        print("   \(error.errorDescription ?? "Unknown error")")
        if let suggestion = error.recoverySuggestion {
            print("   💡 Suggestion: \(suggestion)")
        }
        #endif

        // In production, send to crash reporting service
        // Example: Crashlytics.crashlytics().record(error: error)
    }

    func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        #if DEBUG
        print("⚠️ WARNING in \(fileName):\(line) - \(function)")
        print("   \(message)")
        #endif
    }
}

// MARK: - Error Recovery Actions

protocol ErrorRecoverable {
    func attemptRecovery(from error: AppError) async -> Bool
}

class ErrorRecoveryHandler: ErrorRecoverable {

    func attemptRecovery(from error: AppError) async -> Bool {
        switch error {
        case .networkUnavailable:
            return await retryWithNetwork()
        case .insufficientMemory:
            return await freeUpMemory()
        case .documentCorrupted:
            return await attemptDocumentRepair()
        default:
            return false
        }
    }

    private func retryWithNetwork() async -> Bool {
        // Implement network retry logic
        return false
    }

    private func freeUpMemory() async -> Bool {
        // Clear caches and temporary files
        URLCache.shared.removeAllCachedResponses()
        return true
    }

    private func attemptDocumentRepair() async -> Bool {
        // Attempt to repair corrupted document
        return false
    }
}

// MARK: - Result Extension for Error Handling

extension Result where Failure == AppError {

    @discardableResult
    func logIfFailure() -> Result<Success, Failure> {
        if case .failure(let error) = self {
            ErrorLogger.shared.log(error)
        }
        return self
    }
}