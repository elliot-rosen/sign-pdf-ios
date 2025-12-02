//
//  NoteEditor.swift
//  SignSimplePDF
//
//  Sticky note style popup editor for PDF notes
//

import UIKit

// MARK: - Note Editor Delegate
public protocol NoteEditorDelegate: AnyObject {
    func noteEditor(_ editor: NoteEditor, didUpdateNote note: String)
    func noteEditorDidFinishEditing(_ editor: NoteEditor)
    func noteEditorDidDelete(_ editor: NoteEditor)
}

// MARK: - Note Editor
public class NoteEditor: UIView {
    // MARK: - Properties
    public weak var delegate: NoteEditorDelegate?

    private let containerView = UIView()
    private let headerView = UIView()
    private let textView = UITextView()
    private let authorLabel = UILabel()
    private let timestampLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let resizeHandle = UIImageView()

    private var annotation: UnifiedAnnotation?
    private var noteAnchorPoint: CGPoint = .zero

    // Visual properties
    private let noteColor = UIColor.systemYellow
    private let shadowRadius: CGFloat = 12
    private let minSize = CGSize(width: 200, height: 150)
    private let maxSize = CGSize(width: 400, height: 400)

    // Gesture state
    private var initialSize: CGSize = .zero
    private var isResizing = false

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = .clear

        // Container with shadow
        containerView.backgroundColor = noteColor
        containerView.layer.cornerRadius = 4
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.2
        containerView.layer.shadowOffset = CGSize(width: 2, height: 4)
        containerView.layer.shadowRadius = shadowRadius
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Header
        headerView.backgroundColor = noteColor.withBrightness(0.9)
        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Close button
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .darkGray
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Delete button
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        // Author label
        authorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        authorLabel.textColor = .darkGray
        authorLabel.text = "Note"
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        // Timestamp label
        timestampLabel.font = .systemFont(ofSize: 10)
        timestampLabel.textColor = .darkGray
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        // Text view
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .darkText
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        // Resize handle
        resizeHandle.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        resizeHandle.tintColor = .darkGray.withAlphaComponent(0.3)
        resizeHandle.contentMode = .scaleAspectFit
        resizeHandle.isUserInteractionEnabled = true
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        // Add line pattern to look like lined paper
        addLinePattern()

        // Build hierarchy
        addSubview(containerView)
        containerView.addSubview(headerView)
        containerView.addSubview(textView)
        containerView.addSubview(resizeHandle)
        headerView.addSubview(authorLabel)
        headerView.addSubview(timestampLabel)
        headerView.addSubview(deleteButton)
        headerView.addSubview(closeButton)

        // Apply constraints
        NSLayoutConstraint.activate([
            // Container fills self
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Header
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            // Close button
            closeButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            // Delete button
            deleteButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),

            // Author label
            authorLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),

            // Timestamp label
            timestampLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            timestampLabel.leadingAnchor.constraint(equalTo: authorLabel.trailingAnchor, constant: 8),

            // Text view
            textView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),

            // Resize handle
            resizeHandle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            resizeHandle.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            resizeHandle.widthAnchor.constraint(equalToConstant: 16),
            resizeHandle.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Add fold effect
        addFoldEffect()
    }

    private func addLinePattern() {
        // Create lined paper effect
        let lineLayer = CAShapeLayer()
        lineLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.1).cgColor
        lineLayer.lineWidth = 1

        let path = UIBezierPath()
        let lineSpacing: CGFloat = 24

        for y in stride(from: 56, to: 400, by: lineSpacing) {
            path.move(to: CGPoint(x: 8, y: y))
            path.addLine(to: CGPoint(x: 392, y: y))
        }

        lineLayer.path = path.cgPath
        containerView.layer.insertSublayer(lineLayer, at: 0)
    }

    private func addFoldEffect() {
        // Add subtle gradient to simulate paper fold
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 10, height: 32)
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.05).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        headerView.layer.insertSublayer(gradient, at: 0)
    }

    // MARK: - Gestures
    private func setupGestures() {
        // Pan gesture for moving
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        headerView.addGestureRecognizer(panGesture)

        // Resize gesture
        let resizeGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
        resizeHandle.addGestureRecognizer(resizeGesture)

        // Tap outside to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside(_:)))
        tapGesture.delegate = self
        if let superview = superview {
            superview.addGestureRecognizer(tapGesture)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }

        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            center = CGPoint(
                x: center.x + translation.x,
                y: center.y + translation.y
            )
            gesture.setTranslation(.zero, in: superview)

        default:
            break
        }
    }

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            initialSize = bounds.size
            isResizing = true

        case .changed:
            let newWidth = max(minSize.width, min(maxSize.width, initialSize.width + translation.x))
            let newHeight = max(minSize.height, min(maxSize.height, initialSize.height + translation.y))

            bounds.size = CGSize(width: newWidth, height: newHeight)

        case .ended, .cancelled:
            isResizing = false

        default:
            break
        }
    }

    @objc private func handleTapOutside(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if !bounds.contains(location) {
            closeTapped()
        }
    }

    // MARK: - Public Methods
    public func showNote(for annotation: UnifiedAnnotation, at point: CGPoint, in containerView: UIView) {
        self.annotation = annotation
        self.noteAnchorPoint = point

        // Configure content
        textView.text = annotation.properties.noteContent
        authorLabel.text = annotation.properties.noteAuthor.isEmpty ? "Note" : annotation.properties.noteAuthor
        timestampLabel.text = formatDate(annotation.createdAt)

        // Position note
        frame = CGRect(x: point.x, y: point.y, width: 300, height: 250)

        // Ensure note is within bounds
        adjustPositionToFitContainer(containerView)

        // Add to container
        containerView.addSubview(self)

        // Animate in with spring effect
        transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        alpha = 0

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            self.transform = .identity
            self.alpha = 1
        }

        // Focus text view
        textView.becomeFirstResponder()
    }

    public func hideNote(animated: Bool = true) {
        // Save content
        annotation?.properties.noteContent = textView.text
        delegate?.noteEditor(self, didUpdateNote: textView.text)

        textView.resignFirstResponder()

        if animated {
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                    self.alpha = 0
                }
            ) { _ in
                self.removeFromSuperview()
                self.delegate?.noteEditorDidFinishEditing(self)
            }
        } else {
            removeFromSuperview()
            delegate?.noteEditorDidFinishEditing(self)
        }
    }

    // MARK: - Actions
    @objc private func closeTapped() {
        hideNote()
    }

    @objc private func deleteTapped() {
        let alert = UIAlertController(
            title: "Delete Note",
            message: "Are you sure you want to delete this note?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.noteEditorDidDelete(self)
            self.hideNote(animated: true)
        })

        if let viewController = window?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }

    // MARK: - Helper Methods
    private func adjustPositionToFitContainer(_ container: UIView) {
        var adjustedFrame = frame

        // Right edge
        if adjustedFrame.maxX > container.bounds.width {
            adjustedFrame.origin.x = container.bounds.width - adjustedFrame.width - 20
        }

        // Bottom edge
        if adjustedFrame.maxY > container.bounds.height {
            adjustedFrame.origin.y = container.bounds.height - adjustedFrame.height - 20
        }

        // Left edge
        if adjustedFrame.minX < 0 {
            adjustedFrame.origin.x = 20
        }

        // Top edge
        if adjustedFrame.minY < 0 {
            adjustedFrame.origin.y = 20
        }

        frame = adjustedFrame
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - UITextViewDelegate
extension NoteEditor: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        annotation?.properties.noteContent = textView.text
        delegate?.noteEditor(self, didUpdateNote: textView.text)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension NoteEditor: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle taps outside the note
        let location = touch.location(in: self)
        return !bounds.contains(location)
    }
}

// MARK: - UIColor Extension
private extension UIColor {
    func withBrightness(_ brightness: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var currentBrightness: CGFloat = 0
        var alpha: CGFloat = 0

        getHue(&hue, saturation: &saturation, brightness: &currentBrightness, alpha: &alpha)

        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
}