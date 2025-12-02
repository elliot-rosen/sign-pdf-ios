//
//  PropertyInspector.swift
//  SignSimplePDF
//
//  Floating property inspector panel for annotation customization
//

import UIKit
import Combine

// MARK: - Property Inspector Delegate
public protocol PropertyInspectorDelegate: AnyObject {
    func inspector(_ inspector: PropertyInspector, didChangeStrokeColor color: UIColor)
    func inspector(_ inspector: PropertyInspector, didChangeFillColor color: UIColor?)
    func inspector(_ inspector: PropertyInspector, didChangeStrokeWidth width: CGFloat)
    func inspector(_ inspector: PropertyInspector, didChangeFontSize size: CGFloat)
    func inspector(_ inspector: PropertyInspector, didChangeFontName name: String)
    func inspector(_ inspector: PropertyInspector, didChangeOpacity opacity: CGFloat)
    func inspector(_ inspector: PropertyInspector, didChangeCornerRadius radius: CGFloat)
    func inspector(_ inspector: PropertyInspector, didChangeDashPattern pattern: [CGFloat]?)
    func inspector(_ inspector: PropertyInspector, didChangeArrowStyle style: AnnotationProperties.ArrowHeadStyle)
    func inspectorDidClose(_ inspector: PropertyInspector)
}

// MARK: - Property Inspector
public class PropertyInspector: UIView {
    // MARK: - Properties
    public weak var delegate: PropertyInspectorDelegate?
    public weak var annotationEngine: PDFAnnotationEngine?

    @Published public private(set) var selectedAnnotation: UnifiedAnnotation?

    private var cancellables = Set<AnyCancellable>()

    // UI Components
    private let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    // Property controls
    private var strokeColorButton: UIButton!
    private var fillColorButton: UIButton!
    private var strokeWidthSlider: UISlider!
    private var strokeWidthLabel: UILabel!
    private var fontSizeSlider: UISlider!
    private var fontSizeLabel: UILabel!
    private var fontPickerButton: UIButton!
    private var opacitySlider: UISlider!
    private var opacityLabel: UILabel!
    private var cornerRadiusSlider: UISlider!
    private var cornerRadiusLabel: UILabel!
    private var dashPatternSegment: UISegmentedControl!
    private var arrowStyleSegment: UISegmentedControl!

    // Color picker
    private var activeColorPicker: UIColorPickerViewController?
    private var isSelectingStrokeColor = true

    // Configuration
    public var cornerRadius: CGFloat = 12.0 {
        didSet { updateAppearance() }
    }

    public var preferredWidth: CGFloat = 280
    public var padding: UIEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    // MARK: - Initialization
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupBindings()
    }

    // MARK: - Setup
    private func setupView() {
        // Configure self
        translatesAutoresizingMaskIntoConstraints = false

        // Configure visual effect
        visualEffectView.layer.cornerRadius = cornerRadius
        visualEffectView.layer.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 12

        // Configure scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        // Configure content stack
        contentStackView.axis = .vertical
        contentStackView.spacing = 16
        contentStackView.alignment = .fill
        contentStackView.distribution = .fill
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        // Configure title
        titleLabel.text = "Properties"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textAlignment = .left

        // Configure close button
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        // Build hierarchy
        addSubview(visualEffectView)
        visualEffectView.contentView.addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        // Add header
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.distribution = .fill
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(closeButton)

        contentStackView.addArrangedSubview(headerStack)
        contentStackView.addArrangedSubview(createSeparator())

        // Setup property controls
        setupPropertyControls()

        // Apply constraints
        NSLayoutConstraint.activate([
            // Visual effect
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: visualEffectView.contentView.topAnchor, constant: padding.top),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor, constant: padding.left),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor, constant: -padding.right),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor, constant: -padding.bottom),

            // Content stack
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Size
            widthAnchor.constraint(equalToConstant: preferredWidth),

            // Close button
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Initially hidden
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    }

    private func setupPropertyControls() {
        // Stroke Color
        let strokeColorSection = createSection(title: "Stroke Color")
        strokeColorButton = createColorButton()
        strokeColorButton.addTarget(self, action: #selector(strokeColorButtonTapped), for: .touchUpInside)
        strokeColorSection.addArrangedSubview(strokeColorButton)
        contentStackView.addArrangedSubview(strokeColorSection)

        // Fill Color
        let fillColorSection = createSection(title: "Fill Color")
        fillColorButton = createColorButton()
        fillColorButton.addTarget(self, action: #selector(fillColorButtonTapped), for: .touchUpInside)
        fillColorSection.addArrangedSubview(fillColorButton)
        contentStackView.addArrangedSubview(fillColorSection)

        // Stroke Width
        let strokeWidthSection = createSection(title: "Stroke Width")
        let strokeWidthStack = UIStackView()
        strokeWidthStack.axis = .horizontal
        strokeWidthStack.spacing = 8
        strokeWidthStack.alignment = .center

        strokeWidthSlider = UISlider()
        strokeWidthSlider.minimumValue = 0.5
        strokeWidthSlider.maximumValue = 20
        strokeWidthSlider.value = 2
        strokeWidthSlider.addTarget(self, action: #selector(strokeWidthChanged(_:)), for: .valueChanged)

        strokeWidthLabel = UILabel()
        strokeWidthLabel.text = "2.0"
        strokeWidthLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        strokeWidthLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        strokeWidthStack.addArrangedSubview(strokeWidthSlider)
        strokeWidthStack.addArrangedSubview(strokeWidthLabel)
        strokeWidthSection.addArrangedSubview(strokeWidthStack)
        contentStackView.addArrangedSubview(strokeWidthSection)

        // Font Size
        let fontSizeSection = createSection(title: "Font Size")
        let fontSizeStack = UIStackView()
        fontSizeStack.axis = .horizontal
        fontSizeStack.spacing = 8
        fontSizeStack.alignment = .center

        fontSizeSlider = UISlider()
        fontSizeSlider.minimumValue = 8
        fontSizeSlider.maximumValue = 72
        fontSizeSlider.value = 14
        fontSizeSlider.addTarget(self, action: #selector(fontSizeChanged(_:)), for: .valueChanged)

        fontSizeLabel = UILabel()
        fontSizeLabel.text = "14"
        fontSizeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        fontSizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        fontSizeStack.addArrangedSubview(fontSizeSlider)
        fontSizeStack.addArrangedSubview(fontSizeLabel)
        fontSizeSection.addArrangedSubview(fontSizeStack)
        contentStackView.addArrangedSubview(fontSizeSection)

        // Font Picker
        let fontSection = createSection(title: "Font")
        fontPickerButton = UIButton(type: .system)
        fontPickerButton.setTitle("Helvetica", for: .normal)
        fontPickerButton.contentHorizontalAlignment = .left
        fontPickerButton.addTarget(self, action: #selector(fontPickerButtonTapped), for: .touchUpInside)
        fontSection.addArrangedSubview(fontPickerButton)
        contentStackView.addArrangedSubview(fontSection)

        // Opacity
        let opacitySection = createSection(title: "Opacity")
        let opacityStack = UIStackView()
        opacityStack.axis = .horizontal
        opacityStack.spacing = 8
        opacityStack.alignment = .center

        opacitySlider = UISlider()
        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 1
        opacitySlider.value = 1
        opacitySlider.addTarget(self, action: #selector(opacityChanged(_:)), for: .valueChanged)

        opacityLabel = UILabel()
        opacityLabel.text = "100%"
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        opacityLabel.widthAnchor.constraint(equalToConstant: 45).isActive = true

        opacityStack.addArrangedSubview(opacitySlider)
        opacityStack.addArrangedSubview(opacityLabel)
        opacitySection.addArrangedSubview(opacityStack)
        contentStackView.addArrangedSubview(opacitySection)

        // Corner Radius
        let cornerRadiusSection = createSection(title: "Corner Radius")
        let cornerRadiusStack = UIStackView()
        cornerRadiusStack.axis = .horizontal
        cornerRadiusStack.spacing = 8
        cornerRadiusStack.alignment = .center

        cornerRadiusSlider = UISlider()
        cornerRadiusSlider.minimumValue = 0
        cornerRadiusSlider.maximumValue = 50
        cornerRadiusSlider.value = 0
        cornerRadiusSlider.addTarget(self, action: #selector(cornerRadiusChanged(_:)), for: .valueChanged)

        cornerRadiusLabel = UILabel()
        cornerRadiusLabel.text = "0"
        cornerRadiusLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        cornerRadiusLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        cornerRadiusStack.addArrangedSubview(cornerRadiusSlider)
        cornerRadiusStack.addArrangedSubview(cornerRadiusLabel)
        cornerRadiusSection.addArrangedSubview(cornerRadiusStack)
        contentStackView.addArrangedSubview(cornerRadiusSection)

        // Dash Pattern
        let dashSection = createSection(title: "Line Style")
        dashPatternSegment = UISegmentedControl(items: ["Solid", "Dashed", "Dotted"])
        dashPatternSegment.selectedSegmentIndex = 0
        dashPatternSegment.addTarget(self, action: #selector(dashPatternChanged(_:)), for: .valueChanged)
        dashSection.addArrangedSubview(dashPatternSegment)
        contentStackView.addArrangedSubview(dashSection)

        // Arrow Style
        let arrowSection = createSection(title: "Arrow Style")
        arrowStyleSegment = UISegmentedControl(items: ["None", "Open", "Closed", "Circle"])
        arrowStyleSegment.selectedSegmentIndex = 1
        arrowStyleSegment.addTarget(self, action: #selector(arrowStyleChanged(_:)), for: .valueChanged)
        arrowSection.addArrangedSubview(arrowStyleSegment)
        contentStackView.addArrangedSubview(arrowSection)

        // Initially hide all sections
        updateVisibleSections(for: nil)
    }

    // MARK: - Bindings
    private func setupBindings() {
        // Bind to annotation engine selection
        annotationEngine?.$selectedAnnotation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotation in
                self?.updateForAnnotation(annotation)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update for Annotation
    private func updateForAnnotation(_ annotation: UnifiedAnnotation?) {
        selectedAnnotation = annotation

        if let annotation = annotation {
            // Show inspector
            show()

            // Update controls with annotation properties
            strokeColorButton.backgroundColor = annotation.properties.strokeColor
            fillColorButton.backgroundColor = annotation.properties.fillColor ?? .clear
            strokeWidthSlider.value = Float(annotation.properties.strokeWidth)
            strokeWidthLabel.text = String(format: "%.1f", annotation.properties.strokeWidth)
            fontSizeSlider.value = Float(annotation.properties.fontSize)
            fontSizeLabel.text = "\(Int(annotation.properties.fontSize))"
            fontPickerButton.setTitle(annotation.properties.fontName, for: .normal)
            opacitySlider.value = Float(annotation.properties.opacity)
            opacityLabel.text = "\(Int(annotation.properties.opacity * 100))%"
            cornerRadiusSlider.value = Float(annotation.properties.cornerRadius)
            cornerRadiusLabel.text = "\(Int(annotation.properties.cornerRadius))"

            // Update dash pattern
            if annotation.properties.lineDashPattern == nil {
                dashPatternSegment.selectedSegmentIndex = 0
            } else if annotation.properties.lineDashPattern == [4, 4] {
                dashPatternSegment.selectedSegmentIndex = 1
            } else {
                dashPatternSegment.selectedSegmentIndex = 2
            }

            // Update arrow style
            switch annotation.properties.arrowHeadStyle {
            case .none:
                arrowStyleSegment.selectedSegmentIndex = 0
            case .open:
                arrowStyleSegment.selectedSegmentIndex = 1
            case .closed:
                arrowStyleSegment.selectedSegmentIndex = 2
            case .circle:
                arrowStyleSegment.selectedSegmentIndex = 3
            default:
                arrowStyleSegment.selectedSegmentIndex = 0
            }

            // Show/hide relevant sections
            updateVisibleSections(for: annotation)
        } else {
            // Hide inspector
            hide()
        }
    }

    private func updateVisibleSections(for annotation: UnifiedAnnotation?) {
        guard let annotation = annotation else {
            // Hide all property sections
            contentStackView.arrangedSubviews.forEach { $0.isHidden = true }
            return
        }

        // Show title and separator
        contentStackView.arrangedSubviews[0].isHidden = false
        contentStackView.arrangedSubviews[1].isHidden = false

        // Show/hide sections based on tool
        let sectionsToShow: Set<String>
        switch annotation.tool {
        case .pen, .highlighter:
            sectionsToShow = ["Stroke Color", "Stroke Width", "Opacity"]
        case .text:
            sectionsToShow = ["Stroke Color", "Font Size", "Font", "Opacity"]
        case .arrow, .line:
            sectionsToShow = ["Stroke Color", "Stroke Width", "Line Style", "Arrow Style"]
        case .rectangle, .oval:
            sectionsToShow = ["Stroke Color", "Fill Color", "Stroke Width", "Corner Radius", "Opacity"]
        case .signature, .note:
            sectionsToShow = ["Opacity"]
        default:
            sectionsToShow = []
        }

        // Update visibility
        for (index, view) in contentStackView.arrangedSubviews.enumerated() {
            if index < 2 { continue } // Skip header and separator

            if let stackView = view as? UIStackView,
               let label = stackView.arrangedSubviews.first as? UILabel {
                view.isHidden = !sectionsToShow.contains(label.text ?? "")
            }
        }
    }

    // MARK: - Actions
    @objc private func closeButtonTapped() {
        hide()
        delegate?.inspectorDidClose(self)
    }

    @objc private func strokeColorButtonTapped() {
        isSelectingStrokeColor = true
        showColorPicker(currentColor: selectedAnnotation?.properties.strokeColor ?? .black)
    }

    @objc private func fillColorButtonTapped() {
        isSelectingStrokeColor = false
        showColorPicker(currentColor: selectedAnnotation?.properties.fillColor ?? .white)
    }

    @objc private func strokeWidthChanged(_ sender: UISlider) {
        let width = CGFloat(sender.value)
        strokeWidthLabel.text = String(format: "%.1f", width)

        selectedAnnotation?.properties.strokeWidth = width
        delegate?.inspector(self, didChangeStrokeWidth: width)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    @objc private func fontSizeChanged(_ sender: UISlider) {
        let size = CGFloat(Int(sender.value))
        fontSizeLabel.text = "\(Int(size))"

        selectedAnnotation?.properties.fontSize = size
        delegate?.inspector(self, didChangeFontSize: size)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    @objc private func fontPickerButtonTapped() {
        showFontPicker()
    }

    @objc private func opacityChanged(_ sender: UISlider) {
        let opacity = CGFloat(sender.value)
        opacityLabel.text = "\(Int(opacity * 100))%"

        selectedAnnotation?.properties.opacity = opacity
        delegate?.inspector(self, didChangeOpacity: opacity)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    @objc private func cornerRadiusChanged(_ sender: UISlider) {
        let radius = CGFloat(Int(sender.value))
        cornerRadiusLabel.text = "\(Int(radius))"

        selectedAnnotation?.properties.cornerRadius = radius
        delegate?.inspector(self, didChangeCornerRadius: radius)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    @objc private func dashPatternChanged(_ sender: UISegmentedControl) {
        let pattern: [CGFloat]?
        switch sender.selectedSegmentIndex {
        case 0:
            pattern = nil
        case 1:
            pattern = [4, 4]
        case 2:
            pattern = [2, 2]
        default:
            pattern = nil
        }

        selectedAnnotation?.properties.lineDashPattern = pattern
        delegate?.inspector(self, didChangeDashPattern: pattern)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    @objc private func arrowStyleChanged(_ sender: UISegmentedControl) {
        let styles: [AnnotationProperties.ArrowHeadStyle] = [.none, .open, .closed, .circle]
        let style = styles[sender.selectedSegmentIndex]

        selectedAnnotation?.properties.arrowHeadStyle = style
        delegate?.inspector(self, didChangeArrowStyle: style)
        annotationEngine?.updateAnnotation(selectedAnnotation!)
    }

    // MARK: - Color Picker
    private func showColorPicker(currentColor: UIColor) {
        let colorPicker = UIColorPickerViewController()
        colorPicker.delegate = self
        colorPicker.selectedColor = currentColor
        colorPicker.supportsAlpha = true

        activeColorPicker = colorPicker

        if let viewController = window?.rootViewController {
            viewController.present(colorPicker, animated: true)
        }
    }

    // MARK: - Font Picker
    private func showFontPicker() {
        let fontPicker = UIFontPickerViewController()
        fontPicker.delegate = self

        if let viewController = window?.rootViewController {
            viewController.present(fontPicker, animated: true)
        }
    }

    // MARK: - Show/Hide
    public func show() {
        guard alpha == 0 else { return }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut]
        ) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    public func hide() {
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }
        )
    }

    // MARK: - Helper Methods
    private func createSection(title: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel

        stack.addArrangedSubview(label)
        return stack
    }

    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func createColorButton() -> UIButton {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func updateAppearance() {
        visualEffectView.layer.cornerRadius = cornerRadius
    }
}

// MARK: - UIColorPickerViewControllerDelegate
extension PropertyInspector: UIColorPickerViewControllerDelegate {
    public func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        activeColorPicker = nil
    }

    public func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        if isSelectingStrokeColor {
            strokeColorButton.backgroundColor = color
            selectedAnnotation?.properties.strokeColor = color
            delegate?.inspector(self, didChangeStrokeColor: color)
        } else {
            fillColorButton.backgroundColor = color
            selectedAnnotation?.properties.fillColor = color
            delegate?.inspector(self, didChangeFillColor: color)
        }

        if !continuously {
            annotationEngine?.updateAnnotation(selectedAnnotation!)
        }
    }
}

// MARK: - UIFontPickerViewControllerDelegate
extension PropertyInspector: UIFontPickerViewControllerDelegate {
    public func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
        if let descriptor = viewController.selectedFontDescriptor,
           let fontName = descriptor.object(forKey: .name) as? String {
            fontPickerButton.setTitle(fontName, for: .normal)
            selectedAnnotation?.properties.fontName = fontName
            delegate?.inspector(self, didChangeFontName: fontName)
            annotationEngine?.updateAnnotation(selectedAnnotation!)
        }
    }
}