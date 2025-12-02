//
//  InlineTextEditor.swift
//  SignSimplePDF
//
//  Floating inline text editor that appears directly on the PDF
//

import UIKit

// MARK: - Inline Text Editor Delegate
public protocol InlineTextEditorDelegate: AnyObject {
    func textEditor(_ editor: InlineTextEditor, didUpdateText text: String)
    func textEditorDidFinishEditing(_ editor: InlineTextEditor)
    func textEditorDidCancel(_ editor: InlineTextEditor)
}

// MARK: - Inline Text Editor
public class InlineTextEditor: UIView {
    // MARK: - Properties
    public weak var delegate: InlineTextEditorDelegate?

    private let textView = UITextView()
    private let toolbar = UIView()
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let fontSizeSlider = UISlider()
    private let fontSizeLabel = UILabel()
    private let colorButtons: [UIButton] = []

    private var annotation: UnifiedAnnotation?
    private var keyboardHeight: CGFloat = 0

    // Visual properties
    private let cornerRadius: CGFloat = 8
    private let padding: CGFloat = 8
    private let toolbarHeight: CGFloat = 44

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupKeyboardObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupKeyboardObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup
    private func setupView() {
        // Configure self
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8

        // Setup text view
        setupTextView()

        // Setup toolbar
        setupToolbar()

        // Layout
        addSubview(textView)
        addSubview(toolbar)

        textView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Text view
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            // Toolbar
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight)
        ])
    }

    private func setupTextView() {
        textView.backgroundColor = .systemBackground.withAlphaComponent(0.95)
        textView.layer.cornerRadius = cornerRadius
        textView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .label
        textView.delegate = self
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = true

        // Remove default background
        textView.backgroundColor = .systemBackground.withAlphaComponent(0.98)
    }

    private func setupToolbar() {
        toolbar.backgroundColor = .systemGray6.withAlphaComponent(0.98)
        toolbar.layer.cornerRadius = cornerRadius
        toolbar.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // Cancel button
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .systemRed
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        // Done button
        doneButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        doneButton.tintColor = .systemGreen
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        // Font size controls
        fontSizeSlider.minimumValue = 10
        fontSizeSlider.maximumValue = 48
        fontSizeSlider.value = 14
        fontSizeSlider.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        fontSizeSlider.isContinuous = true

        fontSizeLabel.text = "14"
        fontSizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        fontSizeLabel.textColor = .secondaryLabel

        // Color buttons
        let colors: [UIColor] = [.black, .systemBlue, .systemRed, .systemGreen, .systemOrange]
        var colorButtons: [UIButton] = []

        for color in colors {
            let button = UIButton(type: .system)
            button.backgroundColor = color
            button.layer.cornerRadius = 12
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.clear.cgColor
            button.addTarget(self, action: #selector(colorButtonTapped(_:)), for: .touchUpInside)
            colorButtons.append(button)
        }

        // Stack view for layout
        let colorStack = UIStackView(arrangedSubviews: colorButtons)
        colorStack.axis = .horizontal
        colorStack.spacing = 8
        colorStack.distribution = .fillEqually

        let fontStack = UIStackView(arrangedSubviews: [fontSizeSlider, fontSizeLabel])
        fontStack.axis = .horizontal
        fontStack.spacing = 8

        let mainStack = UIStackView(arrangedSubviews: [cancelButton, colorStack, fontStack, doneButton])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(mainStack)

        // Constraints
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            mainStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            cancelButton.widthAnchor.constraint(equalToConstant: 30),
            cancelButton.heightAnchor.constraint(equalToConstant: 30),

            doneButton.widthAnchor.constraint(equalToConstant: 30),
            doneButton.heightAnchor.constraint(equalToConstant: 30),

            fontSizeSlider.widthAnchor.constraint(equalToConstant: 80),
            fontSizeLabel.widthAnchor.constraint(equalToConstant: 25),

            colorStack.widthAnchor.constraint(equalToConstant: 136), // 5 * 24 + 4 * 4
            colorStack.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Set constraints for color buttons
        for button in colorButtons {
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
    }

    // MARK: - Keyboard Handling
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        keyboardHeight = keyboardFrame.height

        UIView.animate(withDuration: duration) {
            self.adjustPositionForKeyboard()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        keyboardHeight = 0

        UIView.animate(withDuration: duration) {
            self.adjustPositionForKeyboard()
        }
    }

    private func adjustPositionForKeyboard() {
        guard let superview = superview else { return }

        // Calculate if we need to move up to avoid keyboard
        let bottomY = frame.maxY
        let screenHeight = superview.bounds.height
        let keyboardTop = screenHeight - keyboardHeight

        if bottomY > keyboardTop {
            // Move up
            let offset = bottomY - keyboardTop + 20 // 20pt padding
            transform = CGAffineTransform(translationX: 0, y: -offset)
        } else {
            // Reset
            transform = .identity
        }
    }

    // MARK: - Public Methods
    public func startEditing(annotation: UnifiedAnnotation, in containerView: UIView) {
        self.annotation = annotation

        // Configure text view with annotation properties
        textView.text = annotation.properties.text
        textView.font = UIFont(name: annotation.properties.fontName, size: annotation.properties.fontSize)
            ?? .systemFont(ofSize: annotation.properties.fontSize)
        textView.textColor = annotation.properties.strokeColor

        fontSizeSlider.value = Float(annotation.properties.fontSize)
        fontSizeLabel.text = "\(Int(annotation.properties.fontSize))"

        // Position editor over annotation
        let padding: CGFloat = 20
        frame = CGRect(
            x: annotation.frame.origin.x - padding,
            y: annotation.frame.origin.y - padding,
            width: max(200, annotation.frame.width + padding * 2),
            height: max(100, annotation.frame.height + padding * 2 + toolbarHeight)
        )

        // Add to container
        containerView.addSubview(self)

        // Animate in
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.alpha = 1
            self.transform = .identity
        }

        // Focus text view
        textView.becomeFirstResponder()

        // Select all text for easy replacement
        textView.selectAll(nil)
    }

    public func endEditing(save: Bool) {
        textView.resignFirstResponder()

        if save {
            annotation?.properties.text = textView.text
            annotation?.properties.fontSize = CGFloat(fontSizeSlider.value)
            delegate?.textEditor(self, didUpdateText: textView.text)
            delegate?.textEditorDidFinishEditing(self)
        } else {
            delegate?.textEditorDidCancel(self)
        }

        // Animate out
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            self.removeFromSuperview()
        }
    }

    // MARK: - Actions
    @objc private func doneTapped() {
        endEditing(save: true)
    }

    @objc private func cancelTapped() {
        endEditing(save: false)
    }

    @objc private func fontSizeChanged() {
        let fontSize = CGFloat(fontSizeSlider.value)
        fontSizeLabel.text = "\(Int(fontSize))"

        if let font = textView.font {
            textView.font = font.withSize(fontSize)
        } else {
            textView.font = .systemFont(ofSize: fontSize)
        }

        annotation?.properties.fontSize = fontSize
        delegate?.textEditor(self, didUpdateText: textView.text)
    }

    @objc private func colorButtonTapped(_ sender: UIButton) {
        guard let color = sender.backgroundColor else { return }

        textView.textColor = color
        annotation?.properties.strokeColor = color

        // Update button selection state
        for button in toolbar.subviews.compactMap({ $0 as? UIStackView }).first?.arrangedSubviews.compactMap({ $0 as? UIStackView }).first?.arrangedSubviews.compactMap({ $0 as? UIButton }) ?? [] {
            button.layer.borderColor = button == sender ? UIColor.label.cgColor : UIColor.clear.cgColor
        }

        delegate?.textEditor(self, didUpdateText: textView.text)
    }

    // MARK: - Dynamic Sizing
    private func updateSize() {
        // Calculate required size based on text
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 300

        let textSize = textView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))

        let newWidth = min(maxWidth, max(200, textSize.width + padding * 2))
        let newHeight = min(maxHeight, max(100, textSize.height + padding * 2 + toolbarHeight))

        // Animate size change
        UIView.animate(withDuration: 0.2) {
            self.frame.size = CGSize(width: newWidth, height: newHeight)
            self.layoutIfNeeded()
        }
    }
}

// MARK: - UITextViewDelegate
extension InlineTextEditor: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        annotation?.properties.text = textView.text
        delegate?.textEditor(self, didUpdateText: textView.text)
        updateSize()
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle return key if needed
        if text == "\n" && !textView.isFirstResponder {
            doneTapped()
            return false
        }
        return true
    }
}

// MARK: - Keyboard Toolbar
public extension InlineTextEditor {
    func addFormattingToolbar() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let boldButton = UIBarButtonItem(image: UIImage(systemName: "bold"), style: .plain, target: self, action: #selector(toggleBold))
        let italicButton = UIBarButtonItem(image: UIImage(systemName: "italic"), style: .plain, target: self, action: #selector(toggleItalic))
        let underlineButton = UIBarButtonItem(image: UIImage(systemName: "underline"), style: .plain, target: self, action: #selector(toggleUnderline as () -> Void))
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        toolbar.items = [boldButton, italicButton, underlineButton, spacer, doneButton]
        textView.inputAccessoryView = toolbar
    }

    @objc private func toggleBold() {
        // Toggle bold formatting
        if let font = textView.font {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) {
                textView.font = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits.subtracting(.traitBold))!, size: font.pointSize)
            } else {
                textView.font = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits.union(.traitBold))!, size: font.pointSize)
            }
        }
    }

    @objc private func toggleItalic() {
        // Toggle italic formatting
        if let font = textView.font {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitItalic) {
                textView.font = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits.subtracting(.traitItalic))!, size: font.pointSize)
            } else {
                textView.font = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits.union(.traitItalic))!, size: font.pointSize)
            }
        }
    }

    @objc private func toggleUnderline() {
        // Toggle underline - would need NSAttributedString for this
        // For now, just provide haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}