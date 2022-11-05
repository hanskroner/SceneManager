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
            font: font
        )
        textView.delegate = context.coordinator
        textView.storageDelegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ view: CustomTextView, context: Context) {
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
    private var isEditable: Bool
    private var font: NSFont?
    
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
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = false
        scrollView.autoresizingMask = [.width, .height]
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
        textView.autoresizingMask        = .width
        textView.backgroundColor         = NSColor.textBackgroundColor
        textView.delegate                = self.delegate
        textView.drawsBackground         = true
        textView.font                    = self.font
        textView.isEditable              = self.isEditable
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable   = true
        textView.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize                 = NSSize(width: 0, height: contentSize.height)
        textView.textColor               = NSColor.labelColor
        textView.allowsUndo              = true
        
        return textView
    }()
    
    // MARK: - Init
    
    init(text: String, isEditable: Bool, font: NSFont?) {
        self.font       = font
        self.isEditable = isEditable
        self.text       = text
        
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life cycle
    
    override func viewWillDraw() {
        super.viewWillDraw()
        
        setupScrollViewConstraints()
        setupTextView()
    }
    
    func setupScrollViewConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }
    
    func setupTextView() {
        scrollView.documentView = textView
        
        lineNumberView = LineNumberRulerView(textView: self.textView)
        lineNumberView?.ruleThickness = 34
        
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }
}

// MARK: - Line Numbers

class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        clientView = textView.enclosingScrollView!.documentView
        
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: nil) { [weak self] _ in
            self?.needsDisplay = true
        }
        
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: nil) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let textView = textView,
              let textLayoutManager = textView.textLayoutManager
        else {
            return
        }
        
        let relativePoint = self.convert(NSZeroPoint, from: textView)
        
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: isFlipped ? -1 : 1)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textView.font!,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        var lineNumber = 1
        textLayoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { textLayoutFragment in
            for textLineFragment in textLayoutFragment.textLineFragments.reversed() where (textLineFragment.characterRange.length == 0 || textLayoutFragment.textLineFragments.first == textLineFragment) {
                var baselineOffset: CGFloat = 0
                
                if (textLineFragment.characterRange.length == 0) {
                    baselineOffset = -textLineFragment.typographicBounds.height
                }
                
                let locationForFirstCharacter = textLineFragment.glyphOrigin
                let origin = textLayoutFragment.layoutFragmentFrame.origin.applying(.init(translationX: 0, y: locationForFirstCharacter.y + baselineOffset + relativePoint.y))
                let size = CGSize(width: self.ruleThickness, height: textLayoutFragment.layoutFragmentFrame.height)
                let rect = CGRect(origin: origin, size: size)
                let path = CGMutablePath()
                path.addRect(rect)
                
                let attrString = NSAttributedString(string: "\(lineNumber)", attributes: attributes)
                let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attrString.length), path, nil)
                CTFrameDraw(frame, context)
                
                lineNumber += 1
            }
            
            return true
        }
        
        context.restoreGState()
    }
}

// MARK: - Preview

#if DEBUG

struct MacEditorTextView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            SimpleJSONTextView(
                text: .constant(
"""
{
  "bri" : 229,
  "colormode" : "ct",
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
            .previewDisplayName("Dark Mode")
            
            SimpleJSONTextView(
                text: .constant(
"""
{
  "bri" : 229,
  "colormode" : "ct",
  "ct" : 346,
  "on" : true,
  "transitiontime" : 4
}
"""
                ),
                isEditable: false
            )
            .environment(\.colorScheme, .light)
            .previewDisplayName("Light Mode")
        }
    }
}

#endif
