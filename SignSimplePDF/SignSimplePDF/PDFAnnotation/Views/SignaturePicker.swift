//
//  SignaturePicker.swift
//  SignSimplePDF
//
//  Beautiful signature picker UI - grid view with management options
//

import UIKit
import PencilKit
import AVFoundation

// MARK: - Signature Picker Delegate
public protocol SignaturePickerDelegate: AnyObject {
    func signaturePicker(_ picker: SignaturePicker, didSelectSignature signature: Signature)
    func signaturePickerDidCancel(_ picker: SignaturePicker)
    func signaturePicker(_ picker: SignaturePicker, didCreateSignature imageData: Data)
}

// MARK: - Signature Picker
public class SignaturePicker: UIViewController {
    // MARK: - Properties
    public weak var delegate: SignaturePickerDelegate?
    public var signatureManager: SignatureManager?

    private var signatures: [Signature] = []
    private var collectionView: UICollectionView!
    private var emptyStateView: UIView!
    private var canvasView: PKCanvasView?

    // UI Components
    private let titleLabel = UILabel()
    private let segmentControl = UISegmentedControl(items: ["Saved", "Draw", "Camera"])
    private let closeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    private var isEditMode = false
    private var selectedSignatures: Set<IndexPath> = []

    // Camera
    private var imagePickerController: UIImagePickerController?

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadSignatures()
    }

    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground

        // Configure as card presentation
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }

        setupHeader()
        setupSegmentControl()
        setupCollectionView()
        setupDrawingCanvas()
        setupEmptyState()

        // Initially show saved signatures
        segmentControl.selectedSegmentIndex = 0
        segmentChanged()
    }

    private func setupHeader() {
        // Title
        titleLabel.text = "Signatures"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Close button
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Delete button (for edit mode)
        deleteButton.setTitle("Delete", for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        deleteButton.isHidden = true
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        view.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            deleteButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12)
        ])
    }

    private func setupSegmentControl() {
        segmentControl.selectedSegmentIndex = 0
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentControl.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(segmentControl)

        NSLayoutConstraint.activate([
            segmentControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            segmentControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            segmentControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.register(SignatureCell.self, forCellWithReuseIdentifier: "SignatureCell")
        collectionView.register(AddSignatureCell.self, forCellWithReuseIdentifier: "AddSignatureCell")

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupDrawingCanvas() {
        // Canvas for drawing signatures
        canvasView = PKCanvasView()
        canvasView?.backgroundColor = .systemGray6
        canvasView?.layer.cornerRadius = 12
        canvasView?.isHidden = true
        canvasView?.translatesAutoresizingMaskIntoConstraints = false

        if let canvas = canvasView {
            view.addSubview(canvas)

            // Drawing tools
            canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
            canvas.drawingPolicy = .anyInput

            // Clear button
            clearButton.setTitle("Clear", for: .normal)
            clearButton.addTarget(self, action: #selector(clearCanvasTapped), for: .touchUpInside)
            clearButton.translatesAutoresizingMaskIntoConstraints = false
            clearButton.isHidden = true

            // Save button
            saveButton.setTitle("Save Signature", for: .normal)
            saveButton.setStyle(.filled)
            saveButton.addTarget(self, action: #selector(saveSignatureTapped), for: .touchUpInside)
            saveButton.translatesAutoresizingMaskIntoConstraints = false
            saveButton.isHidden = true

            view.addSubview(clearButton)
            view.addSubview(saveButton)

            NSLayoutConstraint.activate([
                canvas.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 20),
                canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                canvas.heightAnchor.constraint(equalToConstant: 200),

                clearButton.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 16),
                clearButton.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),

                saveButton.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 16),
                saveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                saveButton.widthAnchor.constraint(equalToConstant: 200),
                saveButton.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
    }

    private func setupEmptyState() {
        emptyStateView = UIView()
        emptyStateView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(systemName: "signature"))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "No Signatures Yet"
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let subLabel = UILabel()
        subLabel.text = "Tap + to add your first signature"
        subLabel.font = .systemFont(ofSize: 14)
        subLabel.textColor = .tertiaryLabel
        subLabel.textAlignment = .center
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyStateView.addSubview(imageView)
        emptyStateView.addSubview(label)
        emptyStateView.addSubview(subLabel)

        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            imageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),

            subLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            subLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            subLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }

    // MARK: - Data
    private func loadSignatures() {
        signatureManager?.loadSignatures()
        signatures = signatureManager?.signatures ?? []
        collectionView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !signatures.isEmpty || segmentControl.selectedSegmentIndex != 0
    }

    // MARK: - Actions
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
        delegate?.signaturePickerDidCancel(self)
    }

    @objc private func segmentChanged() {
        switch segmentControl.selectedSegmentIndex {
        case 0: // Saved
            showSavedSignatures()
        case 1: // Draw
            showDrawingCanvas()
        case 2: // Camera
            showCamera()
        default:
            break
        }
    }

    @objc private func deleteButtonTapped() {
        guard !selectedSignatures.isEmpty else { return }

        let alert = UIAlertController(
            title: "Delete Signatures",
            message: "Delete \(selectedSignatures.count) signature(s)?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteSelectedSignatures()
        })

        present(alert, animated: true)
    }

    @objc private func clearCanvasTapped() {
        canvasView?.drawing = PKDrawing()
    }

    @objc private func saveSignatureTapped() {
        guard let canvas = canvasView,
              !canvas.drawing.bounds.isEmpty else {
            showAlert(title: "No Signature", message: "Please draw a signature first")
            return
        }

        // Convert drawing to image
        let image = canvas.drawing.image(from: canvas.drawing.bounds, scale: UIScreen.main.scale)
        guard let imageData = image.pngData() else { return }

        // Save signature
        do {
            let drawing = canvas.drawing
            _ = try signatureManager?.saveSignature(
                name: "Signature \(Date())",
                drawing: drawing,
                strokeColor: .black,
                strokeWidth: 3,
                canSaveUnlimited: false
            )
        } catch {
            showAlert(title: "Error", message: error.localizedDescription)
        }

        // Clear canvas and switch to saved
        canvas.drawing = PKDrawing()
        segmentControl.selectedSegmentIndex = 0
        segmentChanged()
        loadSignatures()

        // Notify delegate
        delegate?.signaturePicker(self, didCreateSignature: imageData)
    }

    private func deleteSelectedSignatures() {
        for indexPath in selectedSignatures.sorted(by: { $0.row > $1.row }) {
            if indexPath.row > 0 && indexPath.row <= signatures.count {
                let signature = signatures[indexPath.row - 1]
                signatureManager?.deleteSignature(signature)
            }
        }

        // Reload signatures after deletion
        loadSignatures()

        selectedSignatures.removeAll()
        isEditMode = false
        deleteButton.isHidden = true
        collectionView.reloadData()
        updateEmptyState()
    }

    // MARK: - View Modes
    private func showSavedSignatures() {
        collectionView.isHidden = false
        canvasView?.isHidden = true
        clearButton.isHidden = true
        saveButton.isHidden = true
        updateEmptyState()
    }

    private func showDrawingCanvas() {
        collectionView.isHidden = true
        emptyStateView.isHidden = true
        canvasView?.isHidden = false
        clearButton.isHidden = false
        saveButton.isHidden = false
    }

    private func showCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showAlert(title: "Camera Not Available", message: "Camera is not available on this device")
            segmentControl.selectedSegmentIndex = 0
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.presentCamera()
                } else {
                    self?.showAlert(title: "Camera Access Required", message: "Please enable camera access in Settings")
                    self?.segmentControl.selectedSegmentIndex = 0
                }
            }
        }
    }

    private func presentCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Collection View Data Source
extension SignaturePicker: UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return signatures.count + 1 // +1 for add button
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.row == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AddSignatureCell", for: indexPath) as! AddSignatureCell
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SignatureCell", for: indexPath) as! SignatureCell
            let signature = signatures[indexPath.row - 1]
            cell.configure(with: signature)
            cell.isInEditMode = isEditMode
            return cell
        }
    }
}

// MARK: - Collection View Delegate
extension SignaturePicker: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            // Add button tapped
            segmentControl.selectedSegmentIndex = 1
            segmentChanged()
        } else if isEditMode {
            // Edit mode - select for deletion
            selectedSignatures.insert(indexPath)
            deleteButton.isHidden = selectedSignatures.isEmpty
        } else {
            // Normal mode - select signature
            let signature = signatures[indexPath.row - 1]
            dismiss(animated: true) {
                self.delegate?.signaturePicker(self, didSelectSignature: signature)
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedSignatures.remove(indexPath)
        deleteButton.isHidden = selectedSignatures.isEmpty
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.frame.width - 60) / 2 // 2 columns with padding
        return CGSize(width: width, height: width * 0.5)
    }

    public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row > 0 else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.selectedSignatures = [indexPath]
                self?.deleteSelectedSignatures()
            }

            return UIMenu(title: "", children: [deleteAction])
        }
    }
}

// MARK: - Image Picker Delegate
extension SignaturePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage else { return }

        // Process image for signature
        let processedImage = processImageForSignature(image)
        guard let imageData = processedImage.pngData() else { return }

        // Convert to PKDrawing for saving
        do {
            // Create a simple PKDrawing from the image (this is a workaround)
            let drawing = PKDrawing()
            _ = try signatureManager?.saveSignature(
                name: "Camera Signature",
                drawing: drawing,
                strokeColor: .black,
                strokeWidth: 2,
                canSaveUnlimited: false
            )
            // Update the saved signature with the actual image data
            if let lastSignature = signatureManager?.signatures.first {
                lastSignature.imageData = imageData
                signatureManager?.loadSignatures()
            }
        } catch {
            showAlert(title: "Error", message: error.localizedDescription)
        }

        // Switch back to saved
        segmentControl.selectedSegmentIndex = 0
        segmentChanged()
        loadSignatures()

        delegate?.signaturePicker(self, didCreateSignature: imageData)
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        segmentControl.selectedSegmentIndex = 0
    }

    private func processImageForSignature(_ image: UIImage) -> UIImage {
        // Convert to black and white and remove background
        let ciImage = CIImage(image: image)!

        let filter = CIFilter(name: "CIColorMonochrome")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor")
        filter.setValue(1.0, forKey: "inputIntensity")

        let context = CIContext()
        let outputImage = filter.outputImage!
        let cgImage = context.createCGImage(outputImage, from: outputImage.extent)!

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Signature Cell
class SignatureCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    var isInEditMode = false {
        didSet {
            checkmark.isHidden = !isInEditMode || !isSelected
        }
    }

    override var isSelected: Bool {
        didSet {
            if isInEditMode {
                checkmark.isHidden = !isSelected
            }
            layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.separator.cgColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        contentView.backgroundColor = .systemGray6
        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        checkmark.tintColor = .systemBlue
        checkmark.isHidden = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -4),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            nameLabel.heightAnchor.constraint(equalToConstant: 20),

            checkmark.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with signature: Signature) {
        nameLabel.text = signature.name
        if let imageData = signature.imageData {
            imageView.image = UIImage(data: imageData)
        }
    }
}

// MARK: - Add Signature Cell
class AddSignatureCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        contentView.backgroundColor = .systemGray6
        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        let imageView = UIImageView(image: UIImage(systemName: "plus"))
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Add Signature"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemBlue
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalToConstant: 30),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4)
        ])
    }
}

// MARK: - Button Extension
private extension UIButton {
    func setStyle(_ style: ButtonStyle) {
        switch style {
        case .filled:
            backgroundColor = .systemBlue
            setTitleColor(.white, for: .normal)
            layer.cornerRadius = 8
        case .outline:
            backgroundColor = .clear
            setTitleColor(.systemBlue, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.cornerRadius = 8
        }
    }

    enum ButtonStyle {
        case filled, outline
    }
}