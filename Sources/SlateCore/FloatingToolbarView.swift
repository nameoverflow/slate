import AppKit
import Foundation

private final class ToolbarIconButton: NSView {
    var onClick: (() -> Void)?
    var isSelectedState = false {
        didSet { updateBackground() }
    }
    var isEnabledState = true {
        didSet {
            alphaValue = isEnabledState ? 1.0 : 0.48
            updateBackground()
        }
    }

    private let imageView = NSImageView()
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    init(symbolName: String, tooltip: String, size: CGFloat = 28) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = tooltip

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            imageView.image = img.withSymbolConfiguration(config)
        }
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 18),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabledState else { return }
        alphaValue = 0.7
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabledState else { return }
        alphaValue = 1.0
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            onClick?()
        }
    }

    private func updateBackground() {
        if isSelectedState {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        } else if isHovered && isEnabledState {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private final class ToolbarCopyButton: NSView {
    var onClick: (() -> Void)?
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = "复制到剪贴板 (Enter / 双击)"

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "复制") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            iconView.image = img.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .white
        iconView.imageScaling = .scaleProportionallyDown

        let label = NSTextField(labelWithString: "复制")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white

        let inner = NSStackView(views: [iconView, label])
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 4
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 28),
            inner.centerXAnchor.constraint(equalTo: centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.78
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            onClick?()
        }
    }

    private func updateBackground() {
        layer?.backgroundColor = isHovered
            ? NSColor.systemGreen.cgColor
            : NSColor.systemGreen.withAlphaComponent(0.9).cgColor
    }
}

private final class ToolbarCircleOptionButton: NSView {
    var onClick: (() -> Void)?
    var isSelectedState = false {
        didSet { updateAppearance() }
    }

    private let isColorSwatch: Bool
    private let swatchColor: NSColor

    init(thickness: StrokeThickness) {
        self.isColorSwatch = false
        self.swatchColor = .white
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        layer?.cornerRadius = 11

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.white.cgColor
        dot.layer?.cornerRadius = thickness.dotDiameter * 0.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
            dot.widthAnchor.constraint(equalToConstant: thickness.dotDiameter),
            dot.heightAnchor.constraint(equalToConstant: thickness.dotDiameter),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    init(color: NSColor) {
        self.isColorSwatch = true
        self.swatchColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = color.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            onClick?()
        }
    }

    private func updateAppearance() {
        if isColorSwatch {
            layer?.borderWidth = isSelectedState ? 2.0 : 0.75
            layer?.borderColor = isSelectedState
                ? NSColor.white.cgColor
                : NSColor.white.withAlphaComponent(0.35).cgColor
        } else {
            layer?.backgroundColor = isSelectedState
                ? NSColor.white.withAlphaComponent(0.24).cgColor
                : NSColor.clear.cgColor
        }
    }
}

public final class FloatingToolbarView: NSView {
    public var onSelectTool: ((AnnotationTool) -> Void)?
    public var onSelectColor: ((NSColor) -> Void)?
    public var onSelectThickness: ((StrokeThickness) -> Void)?
    public var onUndo: (() -> Void)?
    public var onSave: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onCopy: (() -> Void)?

    public private(set) var selectedTool: AnnotationTool = .none
    public private(set) var selectedColor: NSColor = AnnotationColorPalette.colors[0]
    public private(set) var selectedThickness: StrokeThickness = .medium
    public private(set) var hasSelectedAnnotation: Bool = false

    private let mainPanel = NSVisualEffectView()
    private let stylePanel = NSVisualEffectView()
    private let mainStack = NSStackView()
    private let styleStack = NSStackView()

    private var toolButtons: [AnnotationTool: ToolbarIconButton] = [:]
    private var undoButton: ToolbarIconButton!
    private var saveButton: ToolbarIconButton!
    private var cancelButton: ToolbarIconButton!
    private var copyButton: ToolbarCopyButton!
    private var colorButtons: [(NSColor, ToolbarCircleOptionButton)] = []
    private var thicknessButtons: [(StrokeThickness, ToolbarCircleOptionButton)] = []

    private let mainHeight: CGFloat = 40
    private let styleHeight: CGFloat = 34
    private let spacing: CGFloat = 6
    private let mainHorizontalPadding: CGFloat = 8
    private let styleHorizontalPadding: CGFloat = 10

    private var mainPanelWidth: CGFloat = 388
    private var stylePanelWidth: CGFloat = 258

    private var showsStylePanel: Bool {
        selectedTool != .none || hasSelectedAnnotation
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupPanels()
        updateSelections()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func requiredSize() -> CGSize {
        let showStyle = showsStylePanel
        let width = max(mainPanelWidth, showStyle ? stylePanelWidth : 0)
        let height = showStyle ? (mainHeight + spacing + styleHeight) : mainHeight
        return CGSize(width: ceil(width), height: ceil(height))
    }

    public func setTool(_ tool: AnnotationTool) {
        selectedTool = tool
        updateSelections()
        needsLayout = true
    }

    public func setHasSelectedAnnotation(_ hasSelection: Bool) {
        hasSelectedAnnotation = hasSelection
        needsLayout = true
    }

    public func setStyle(color: NSColor, thickness: StrokeThickness) {
        selectedColor = color
        selectedThickness = thickness
        updateSelections()
    }

    public func setCanUndo(_ canUndo: Bool) {
        undoButton.isEnabledState = canUndo
    }

    public var isUndoEnabledForTesting: Bool {
        undoButton.isEnabledState
    }

    public func simulateUndoClickForTesting() {
        if undoButton.isEnabledState {
            onUndo?()
        }
    }

    /// Returns frames of main action buttons for layout verification in tests.
    public var mainButtonFramesForTesting: [(String, CGSize)] {
        var result: [(String, CGSize)] = []
        for (tool, btn) in toolButtons {
            result.append((tool.rawValue, btn.frame.size))
        }
        result.append(("undo", undoButton.frame.size))
        result.append(("save", saveButton.frame.size))
        result.append(("cancel", cancelButton.frame.size))
        result.append(("copy", copyButton.frame.size))
        return result
    }

    /// Computes toolbar frame near `selectionRect` within `bounds`, preferring below, then above, then inside bottom.
    public static func preferredFrame(
        forSize size: CGSize,
        selectionRect: CGRect,
        bounds: CGRect
    ) -> CGRect {
        let margin: CGFloat = 10
        let gap: CGFloat = 8

        var x = selectionRect.maxX - size.width
        x = max(bounds.minX + margin, min(x, bounds.maxX - size.width - margin))

        let belowY = selectionRect.minY - gap - size.height
        let aboveY = selectionRect.maxY + gap

        let y: CGFloat
        if belowY >= bounds.minY + margin {
            y = belowY
        } else if aboveY + size.height <= bounds.maxY - margin {
            y = aboveY
        } else {
            y = max(bounds.minY + margin, selectionRect.minY + margin)
        }

        return CGRect(x: round(x), y: round(y), width: size.width, height: size.height)
    }

    public override func layout() {
        super.layout()
        let showStyle = showsStylePanel
        stylePanel.isHidden = !showStyle
        if showStyle {
            mainPanel.frame = CGRect(x: 0, y: styleHeight + spacing, width: mainPanelWidth, height: mainHeight)
            stylePanel.frame = CGRect(x: 0, y: 0, width: stylePanelWidth, height: styleHeight)
        } else {
            mainPanel.frame = CGRect(x: 0, y: 0, width: mainPanelWidth, height: mainHeight)
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if mainPanel.frame.contains(local) {
            return super.hitTest(point)
        }
        if !stylePanel.isHidden && stylePanel.frame.contains(local) {
            return super.hitTest(point)
        }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        // Swallow clicks on the toolbar background so they don't fall through to the canvas.
    }

    private func setupPanels() {
        configureGlassPanel(mainPanel, cornerRadius: 10)
        configureGlassPanel(stylePanel, cornerRadius: 8)
        addSubview(mainPanel)
        addSubview(stylePanel)

        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 4
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainPanel.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: mainPanel.leadingAnchor, constant: mainHorizontalPadding),
            mainStack.centerYAnchor.constraint(equalTo: mainPanel.centerYAnchor)
        ])

        let toolSpecs: [(AnnotationTool, String, String)] = [
            (.none, "cursorarrow", "选择与调整"),
            (.rectangle, "square", "方框"),
            (.ellipse, "circle", "圆圈"),
            (.arrow, "arrow.up.right", "箭头"),
            (.brush, "pencil.tip", "涂画"),
            (.text, "textformat", "文字")
        ]

        for (tool, symbol, tip) in toolSpecs {
            let btn = ToolbarIconButton(symbolName: symbol, tooltip: tip)
            btn.onClick = { [weak self] in
                guard let self = self else { return }
                if tool == .none {
                    self.selectedTool = .none
                } else {
                    self.selectedTool = (self.selectedTool == tool) ? .none : tool
                }
                self.updateSelections()
                self.onSelectTool?(self.selectedTool)
            }
            toolButtons[tool] = btn
            mainStack.addArrangedSubview(btn)
        }

        mainStack.addArrangedSubview(makeSeparator())

        undoButton = ToolbarIconButton(symbolName: "arrow.uturn.backward", tooltip: "撤销 (⌘Z)")
        undoButton.onClick = { [weak self] in self?.onUndo?() }
        setCanUndo(false)
        mainStack.addArrangedSubview(undoButton)

        mainStack.addArrangedSubview(makeSeparator())

        saveButton = ToolbarIconButton(symbolName: "square.and.arrow.down", tooltip: "保存到文件 (⌘S)")
        saveButton.onClick = { [weak self] in self?.onSave?() }
        mainStack.addArrangedSubview(saveButton)

        cancelButton = ToolbarIconButton(symbolName: "xmark", tooltip: "取消 (Esc)")
        cancelButton.onClick = { [weak self] in self?.onCancel?() }
        mainStack.addArrangedSubview(cancelButton)

        copyButton = ToolbarCopyButton()
        copyButton.onClick = { [weak self] in self?.onCopy?() }
        mainStack.addArrangedSubview(copyButton)

        setupStylePanel()

        mainStack.layoutSubtreeIfNeeded()
        styleStack.layoutSubtreeIfNeeded()
        mainPanelWidth = ceil(mainStack.fittingSize.width) + mainHorizontalPadding * 2
        stylePanelWidth = ceil(styleStack.fittingSize.width) + styleHorizontalPadding * 2
    }

    private func setupStylePanel() {
        styleStack.orientation = .horizontal
        styleStack.alignment = .centerY
        styleStack.spacing = 6
        styleStack.translatesAutoresizingMaskIntoConstraints = false
        stylePanel.addSubview(styleStack)

        NSLayoutConstraint.activate([
            styleStack.leadingAnchor.constraint(equalTo: stylePanel.leadingAnchor, constant: styleHorizontalPadding),
            styleStack.centerYAnchor.constraint(equalTo: stylePanel.centerYAnchor)
        ])

        for thickness in StrokeThickness.allCases {
            let btn = ToolbarCircleOptionButton(thickness: thickness)
            btn.onClick = { [weak self] in
                guard let self = self else { return }
                self.selectedThickness = thickness
                self.updateSelections()
                self.onSelectThickness?(thickness)
            }
            thicknessButtons.append((thickness, btn))
            styleStack.addArrangedSubview(btn)
        }

        styleStack.addArrangedSubview(makeSeparator())

        for color in AnnotationColorPalette.colors {
            let btn = ToolbarCircleOptionButton(color: color)
            btn.onClick = { [weak self] in
                guard let self = self else { return }
                self.selectedColor = color
                self.updateSelections()
                self.onSelectColor?(color)
            }
            colorButtons.append((color, btn))
            styleStack.addArrangedSubview(btn)
        }
    }

    private func configureGlassPanel(_ panel: NSVisualEffectView, cornerRadius: CGFloat) {
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = cornerRadius
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.75
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    private func makeSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 18)
        ])
        return view
    }

    private func updateSelections() {
        for (tool, btn) in toolButtons {
            btn.isSelectedState = (tool == selectedTool)
        }
        for (thickness, btn) in thicknessButtons {
            btn.isSelectedState = (thickness == selectedThickness)
        }
        for (color, btn) in colorButtons {
            btn.isSelectedState = AnnotationColorPalette.colorsMatch(color, selectedColor)
        }
    }
}
