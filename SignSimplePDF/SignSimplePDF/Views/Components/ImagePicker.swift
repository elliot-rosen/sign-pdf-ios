import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    let onImagesPicked: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0 // 0 means unlimited
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        private var loadedImages: [UIImage] = []
        private var expectedCount = 0

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            expectedCount = results.count
            loadedImages = []

            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        guard let self = self else { return }

                        DispatchQueue.main.async {
                            if let image = image as? UIImage {
                                self.loadedImages.append(image)
                            }

                            if self.loadedImages.count == self.expectedCount {
                                self.parent.onImagesPicked(self.loadedImages)
                                self.parent.dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}