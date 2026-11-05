//
//  SimpleJSONTextView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct SimpleJSONTextView: NSViewRepresentable {
    @Binding var text: String
    
    var isEditable: Bool = true
    var font: NSFont?    = .monospacedSystemFont(ofSize: 12, weight: .regular)
    
    /// Space kept clear above the first line, e.g. for a floating control.
    /// Text still scrolls underneath it.
    var topContentInset: CGFloat = 0
    
    /// Hides the line numbers while keeping the gutter, so the text doesn't
    /// shift sideways when they come back.
    var showsLineNumbers: Bool = true
    
    var onEditingChanged: () -> Void       = {}
    var onCommit        : () -> Void       = {}
    var onTextChange    : (String) -> Void = { _ in }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> CustomTextView {
        let textView = CustomTextView(
            text: text,
            isEditable: isEditable,
            font: font,
            topContentInset: topContentInset,
            showsLineNumbers: showsLineNumbers
        )
        textView.delegate = context.coordinator
        textView.storageDelegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ view: CustomTextView, context: Context) {
        // Editability can change while the view is alive (e.g. Group vs. Scene
        // selection). A non-editable view still allows selecting and scrolling.
        view.isEditable = isEditable
        view.showsLineNumbers = showsLineNumbers
        view.text = text
        view.selectedRanges = context.coordinator.selectedRanges
    }
}

// MARK: - Coordinator

extension SimpleJSONTextView {
    
    class Coordinator: NSObject, NSTextViewDelegate, NSTextContentStorageDelegate {
        var parent: SimpleJSONTextView
        var selectedRanges: [NSValue] = []
        
        init(_ parent: SimpleJSONTextView) {
            self.parent = parent
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.parent.onEditingChanged()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.selectedRanges = textView.selectedRanges
        }
        
        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.parent.onCommit()
        }
        
        func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            var paragraphWithDisplayAttributes: NSTextParagraph? = nil
            
            let originalString = textContentStorage.textStorage!.attributedSubstring(from: range)
            
            let stringAttributes = [NSAttributedString.Key.foregroundColor: NSColor(Color("string"))]
            let numberAttributes = [NSAttributedString.Key.foregroundColor: NSColor(Color("number"))]
            let booleanAttributes = [NSAttributedString.Key.foregroundColor: NSColor(Color("keyword"))]
            
            let replacements: [String: [NSAttributedString.Key: Any]] = [
                "\"([^\"]+)\"": stringAttributes,
                "([+]|-)?(([0-9]+[.]?[0-9]*)|([0-9]*[.]?[0-9]+))": numberAttributes,
                "true|false": booleanAttributes
            ]
            
            let textWithDisplayAttributes = NSMutableAttributedString(attributedString: originalString)
            for (pattern, attributes) in replacements {
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(originalString.string.startIndex..., in: originalString.string)
                
                regex?.enumerateMatches(in: originalString.string, range: range) { match, flags, stop in
                    if let rangeForDisplayAttributes = match?.range(at: 0) {
                        textWithDisplayAttributes.addAttributes(attributes, range: rangeForDisplayAttributes)
                    }
                }
                
                paragraphWithDisplayAttributes = NSTextParagraph(attributedString: textWithDisplayAttributes)
            }
            
            return paragraphWithDisplayAttributes
        }
    }
}

// MARK: - CustomTextView

final class CustomTextView: NSView {
    var isEditable: Bool {
        didSet {
            guard isEditable != oldValue else { return }
            textView.isEditable = isEditable
        }
    }
    
    private var font: NSFont?
    private var topContentInset: CGFloat
    private var isSetUp = false
    
    var showsLineNumbers: Bool {
        didSet { lineNumberView?.showsNumbers = showsLineNumbers }
    }
    
    weak var delegate: NSTextViewDelegate?
    weak var storageDelegate: NSTextContentStorageDelegate?
    
    var lineNumberView: LineNumberRulerView?
    
    var text: String {
        didSet {
            textView.string = text
            
            if let lineNumberView = lineNumberView {
                lineNumberView.setNeedsDisplay(lineNumberView.visibleRect)
            }
        }
    }
    
    var selectedRanges: [NSValue] = [] {
        didSet {
            guard selectedRanges.count > 0 else {
                return
            }
            
            textView.selectedRanges = selectedRanges
        }
    }
    
    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        // Flat look: the editor shows whatever is behind it instead of
        // painting its own text background.
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        return scrollView
    }()
    
    private lazy var textView: NSTextView = {
        let contentSize = scrollView.contentSize
        
        let textContentStorage = NSTextContentStorage()
        textContentStorage.delegate = self.storageDelegate
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        
        let textContainer = NSTextContainer(size: scrollView.frame.size)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textLayoutManager.textContainer = textContainer
        
        let textView                     = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate                = self.delegate
        textView.font                    = self.font
        textView.isEditable              = self.isEditable
        textView.isSelectable            = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable   = true
        textView.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize                 = NSSize(width: 0, height: contentSize.height)
        textView.drawsBackground         = false
        textView.allowsUndo              = true
        textView.autoresizingMask        = .width
        
        return textView
    }()
    
    // MARK: - Init
    
    init(text: String, isEditable: Bool, font: NSFont?, topContentInset: CGFloat = 0, showsLineNumbers: Bool = true) {
        self.font = font
        self.isEditable = isEditable
        self.topContentInset = topContentInset
        self.showsLineNumbers = showsLineNumbers
        self.text = text
        
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life cycle
    
    override func viewWillDraw() {
        super.viewWillDraw()
        
        // This runs before every draw pass. Set up once, otherwise a new ruler
        // (and a new set of constraints) is created each time, and the ruler
        // can't keep any state such as 'showsNumbers'.
        guard !isSetUp else { return }
        isSetUp = true
        
        addSubview(scrollView)
        scrollView.documentView = textView
        
        // Create Line Number View
        lineNumberView = LineNumberRulerView(textView: self.textView)
        lineNumberView?.ruleThickness = 34
        lineNumberView?.showsNumbers = showsLineNumbers
        
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        // Set layout constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }
}

// MARK: - Line Numbers

class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    
    /// When false the gutter keeps its width, but no numbers are drawn.
    var showsNumbers = true {
        didSet { needsDisplay = true }
    }
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        clientView = textView.enclosingScrollView!.documentView
        
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // The default NSRulerView fills its own background and draws a separator
    // line. Draw only the line numbers, so the gutter is flat like the editor.
    public override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }
    
    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard showsNumbers,
              let context = NSGraphicsContext.current?.cgContext,
              let textView = textView,
              let textLayoutManager = textView.textLayoutManager,
              let font = textView.font
        else {
            return
        }
        
        let textOrigin = textView.textContainerOrigin
        let rightEdge = ruleThickness - 5
        
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: isFlipped ? -1 : 1)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        var lineNumber = 1
        textLayoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { textLayoutFragment in
            for (index, textLineFragment) in textLayoutFragment.textLineFragments.enumerated() where (index == 0 || textLineFragment.characterRange.length == 0) {
                // Place each number on the exact baseline of its text line. Empty
                // lines (including the empty document) go through the same
                // calculation, so a number doesn't move when text is typed. Empty
                // line fragments may not report a baseline, so fall back to the
                // font's ascender.
                let baselineWithinLine = textLineFragment.glyphOrigin.y > 0 ? textLineFragment.glyphOrigin.y : font.ascender
                let baselineInTextView = textOrigin.y
                    + textLayoutFragment.layoutFragmentFrame.origin.y
                    + textLineFragment.typographicBounds.origin.y
                    + baselineWithinLine
                
                // Converting from the text view accounts for scrolling and the
                // scroll view's content insets.
                let baseline = self.convert(NSPoint(x: 0, y: baselineInTextView), from: textView)
                
                let label = CTLineCreateWithAttributedString(NSAttributedString(string: "\(lineNumber)", attributes: attributes))
                let labelWidth = CTLineGetTypographicBounds(label, nil, nil, nil)
                
                context.textPosition = CGPoint(x: rightEdge - labelWidth, y: baseline.y)
                CTLineDraw(label, context)
                
                lineNumber += 1
            }
            
            return true
        }
        
        context.restoreGState()
    }
}

// MARK: - Preview

#if DEBUG

#Preview("Dark Mode") {
    SimpleJSONTextView(
        text: .constant(
"""
{
  "bri" : 229,
  "ct" : 346,
  "on" : true,
  "transitiontime" : 4
}
"""
        ),
        isEditable: true,
        font: .monospacedSystemFont(ofSize: 12, weight: .medium)
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Light Mode") {
    SimpleJSONTextView(
        text: .constant(
"""
{
  "bri" : 229,
  "ct" : 346,
  "on" : true,
  "transitiontime" : 4
}
"""
        ),
        isEditable: false
    )
    .environment(\.colorScheme, .light)
}

#endif
