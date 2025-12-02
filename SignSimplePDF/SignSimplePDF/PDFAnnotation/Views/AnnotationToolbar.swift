//
//  AnnotationToolbar.swift
//  SignSimplePDF
//
//  Beautiful floating annotation toolbar - Apple Preview inspired
//

import UIKit
import Combine

// MARK: - Toolbar Delegate
public protocol AnnotationToolbarDelegate: AnyObject {
    func toolbar(_ toolbar: AnnotationToolbar, didSelectTool tool: AnnotationTool)
    func toolbarDidTapUndo(_ toolbar: AnnotationToolbar)
    func toolbarDidTapRedo(_ toolbar: AnnotationToolbar)
    func toolbarDidTapDone(_ toolbar: AnnotationToolbar)
    func toolbar(_ toolbar: AnnotationToolbar, didChangeVisibility isVisible: Bool)
}

// MARK: - Annotation Toolbar
public class AnnotationToolbar: UIView {
    // MARK: - Properties
    public weak var delegate: AnnotationToolbarDelegate?
    public weak var annotationEngine: PDFAnnotationEngine?

    @Published public private(set) var selectedTool: AnnotationTool = .selection

    private var cancellables = Set<AnyCancellable>()

    // UI Components
    private let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let stackView = UIStackView()
    private let toolScrollView = UIScrollView()
    private let toolStackView = UIStackView()
    private let actionStackView = UIStackView()
    private let separatorView = UIView()

    private var toolButtons: [AnnotationTool: UIButton] = [:]
    private var undoButton: UIButton!
    private var redoButton: UIButton!
    private var doneButton: UIButton!

    // Toolbar position and auto-hide
    private var dragStartPoint: CGPoint = .zero
    private var autoHideTimer: Timer?
    private let autoHideDelay: TimeInterval = 5.0
    private var isAutoHidden = false

    // Animation properties
    private let springDamping: CGFloat = 0.8
    private let springVelocity: CGFloat = 0.5
    private let animationDuration: TimeInterval = 0.3

    // Configuration
    public var cornerRadius: CGFloat = 12.0 {
        didSet { updateAppearance() }
    }

    public var buttonSize: CGSize = CGSize(width: 36, height: 36) {
        didSet { updateLayout() }
    }

    public var padding: UIEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12) {
        didSet { updateLayout() }
    }

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
        setupBindings()
    }

    // MARK: - Setup
    private func setupView() {
        // Configure visual effect
        visualEffectView.layer.cornerRadius = cornerRadius
        visualEffectView.layer.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8

        // Configure stack views
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Configure tool scroll view for horizontal scrolling
        toolScrollView.translatesAutoresizingMaskIntoConstraints = false
        toolScrollView.showsHorizontalScrollIndicator = false
        toolScrollView.showsVerticalScrollIndicator = false
        toolScrollView.bounces = true
        toolScrollView.alwaysBounceHorizontal = true
        toolScrollView.contentInset = .zero

        toolStackView.axis = .horizontal
        toolStackView.spacing = 4
        toolStackView.alignment = .center
        toolStackView.distribution = .fill
        toolStackView.translatesAutoresizingMaskIntoConstraints = false

        actionStackView.axis = .horizontal
        actionStackView.spacing = 4
        actionStackView.alignment = .center
        actionStackView.distribution = .fill
        actionStackView.translatesAutoresizingMaskIntoConstraints = false

        // Configure separator
        separatorView.backgroundColor = UIColor.separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        addSubview(visualEffectView)
        visualEffectView.contentView.addSubview(stackView)

        // Setup buttons
        setupToolButtons()
        setupActionButtons()

        // Add toolStackView to scroll view
        toolScrollView.addSubview(toolStackView)

        // Build hierarchy - tools are always visible (no expand button)
        stackView.addArrangedSubview(toolScrollView)
        stackView.addArrangedSubview(separatorView)
        stackView.addArrangedSubview(actionStackView)
        stackView.addArrangedSubview(doneButton)

        // Apply constraints
        let stackTrailingConstraint = stackView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor, constant: -padding.right)
        stackTrailingConstraint.priority = .defaultHigh // Allow breaking when view is initially sized to 0

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: visualEffectView.contentView.topAnchor, constant: padding.top),
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor, constant: padding.left),
            stackTrailingConstraint,
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor, constant: -padding.bottom),

            // Tool scroll view constraints
            toolScrollView.heightAnchor.constraint(equalToConstant: buttonSize.height),

            // Tool stack view inside scroll view
            toolStackView.topAnchor.constraint(equalTo: toolScrollView.contentLayoutGuide.topAnchor),
            toolStackView.leadingAnchor.constraint(equalTo: toolScrollView.contentLayoutGuide.leadingAnchor),
            toolStackView.trailingAnchor.constraint(equalTo: toolScrollView.contentLayoutGuide.trailingAnchor),
            toolStackView.bottomAnchor.constraint(equalTo: toolScrollView.contentLayoutGuide.bottomAnchor),
            toolStackView.heightAnchor.constraint(equalTo: toolScrollView.frameLayoutGuide.heightAnchor),

            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func setupToolButtons() {
        // Define tools to show
        let tools: [AnnotationTool] = [.selection, .pen, .highlighter, .text, .arrow, .rectangle, .oval, .signature, .note]

        for tool in tools {
            let button = createToolButton(for: tool)
            toolButtons[tool] = button
            toolStackView.addArrangedSubview(button)
        }

        // Select default tool
        selectTool(.selection)
    }

    private func setupActionButtons() {
        // Undo button
        undoButton = createButton(
            systemName: "arrow.uturn.backward",
            action: #selector(undoButtonTapped)
        )

        // Redo button
        redoButton = createButton(
            systemName: "arrow.uturn.forward",
            action: #selector(redoButtonTapped)
        )

        // Done button
        doneButton = createButton(
            systemName: "checkmark",
            action: #selector(doneButtonTapped)
        )
        doneButton.tintColor = .systemGreen

        actionStackView.addArrangedSubview(undoButton)
        actionStackView.addArrangedSubview(redoButton)
    }

    private func createToolButton(for tool: AnnotationTool) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: tool.icon), for: .normal)
        button.tag = tools.firstIndex(of: tool) ?? 0
        button.addTarget(self, action: #selector(toolButtonTapped(_:)), for: .touchUpInside)

        // Configure appearance
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize.width),
            button.heightAnchor.constraint(equalToConstant: buttonSize.height)
        ])

        return button
    }

    private func createButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize.width),
            button.heightAnchor.constraint(equalToConstant: buttonSize.height)
        ])

        return button
    }

    // MARK: - Gestures
    private func setupGestures() {
        // Pan gesture for dragging toolbar
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        // Tap gesture to reset auto-hide timer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }

        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .began:
            dragStartPoint = center
            cancelAutoHide()

        case .changed:
            // Update position
            center = CGPoint(
                x: dragStartPoint.x + translation.x,
                y: dragStartPoint.y + translation.y
            )

            // Magnetic edge snapping
            snapToEdges()

        case .ended:
            // Animate to final snapped position
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: springDamping,
                initialSpringVelocity: springVelocity,
                options: [.curveEaseInOut]
            ) {
                self.snapToEdges()
            }
            startAutoHideTimer()

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        resetAutoHideTimer()
    }

    // MARK: - Edge Snapping
    private func snapToEdges() {
        guard let superview = superview else { return }

        let margin: CGFloat = 16
        let snapDistance: CGFloat = 30

        var newCenter = center

        // Horizontal snapping
        if center.x < snapDistance + bounds.width / 2 {
            newCenter.x = margin + bounds.width / 2
        } else if center.x > superview.bounds.width - snapDistance - bounds.width / 2 {
            newCenter.x = superview.bounds.width - margin - bounds.width / 2
        }

        // Vertical snapping
        if center.y < snapDistance + bounds.height / 2 {
            newCenter.y = margin + bounds.height / 2
        } else if center.y > superview.bounds.height - snapDistance - bounds.height / 2 {
            newCenter.y = superview.bounds.height - margin - bounds.height / 2
        }

        // Apply snapped position with haptic feedback if snapped
        if newCenter != center {
            center = newCenter
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Bindings
    private func setupBindings() {
        // Bind to annotation engine state
        annotationEngine?.$canUndo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canUndo in
                self?.undoButton.isEnabled = canUndo
                self?.undoButton.alpha = canUndo ? 1.0 : 0.3
            }
            .store(in: &cancellables)

        annotationEngine?.$canRedo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canRedo in
                self?.redoButton.isEnabled = canRedo
                self?.redoButton.alpha = canRedo ? 1.0 : 0.3
            }
            .store(in: &cancellables)

        annotationEngine?.$currentTool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tool in
                self?.selectTool(tool)
            }
            .store(in: &cancellables)
    }

    // MARK: - Tool Selection
    public func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool

        // Update button states
        for (buttonTool, button) in toolButtons {
            let isSelected = buttonTool == tool

            UIView.animate(withDuration: 0.2) {
                if isSelected {
                    button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
                    button.tintColor = .systemBlue
                    button.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                } else {
                    button.backgroundColor = .clear
                    button.tintColor = .label
                    button.transform = .identity
                }
            }
        }

        // Haptic feedback
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Actions
    @objc private func toolButtonTapped(_ sender: UIButton) {
        guard let tool = tools[safe: sender.tag] else { return }

        selectTool(tool)
        delegate?.toolbar(self, didSelectTool: tool)
        annotationEngine?.selectTool(tool)

        resetAutoHideTimer()
    }

    @objc private func undoButtonTapped() {
        delegate?.toolbarDidTapUndo(self)
        annotationEngine?.undo()
        resetAutoHideTimer()
    }

    @objc private func redoButtonTapped() {
        delegate?.toolbarDidTapRedo(self)
        annotationEngine?.redo()
        resetAutoHideTimer()
    }

    @objc private func doneButtonTapped() {
        delegate?.toolbarDidTapDone(self)
        resetAutoHideTimer()
    }

    // MARK: - Auto Hide
    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.autoHide()
        }
    }

    private func resetAutoHideTimer() {
        if isAutoHidden {
            autoShow()
        }
        startAutoHideTimer()
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func autoHide() {
        guard !isAutoHidden else { return }

        isAutoHidden = true

        UIView.animate(withDuration: animationDuration) {
            self.alpha = 0.3
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }

        delegate?.toolbar(self, didChangeVisibility: false)
    }

    private func autoShow() {
        guard isAutoHidden else { return }

        isAutoHidden = false

        UIView.animate(withDuration: animationDuration) {
            self.alpha = 1.0
            self.transform = .identity
        }

        delegate?.toolbar(self, didChangeVisibility: true)
    }

    // MARK: - Appearance
    private func updateAppearance() {
        visualEffectView.layer.cornerRadius = cornerRadius
    }

    private func updateLayout() {
        toolButtons.values.forEach { button in
            button.removeConstraints(button.constraints)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: buttonSize.width),
                button.heightAnchor.constraint(equalToConstant: buttonSize.height)
            ])
        }

        [undoButton, redoButton, doneButton].forEach { button in
            button?.removeConstraints(button?.constraints ?? [])
            if let button = button {
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: buttonSize.width),
                    button.heightAnchor.constraint(equalToConstant: buttonSize.height)
                ])
            }
        }

        setNeedsLayout()
    }

    // MARK: - Helper
    private let tools: [AnnotationTool] = [.selection, .pen, .highlighter, .text, .arrow, .rectangle, .oval, .signature, .note]
}

// MARK: - Array Extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}