//
//  SearchField.swift
//  SceneManager
//
//  Created by Hans Kröner on 04/04/2025.
//
//  Adapted from https://github.com/jaywcjlove/swiftui-searchfield

import SwiftUI

@available(macOS 10.15, *)
struct SearchField: NSViewRepresentable {
    // A binding to a string value
    @Binding var text: String
    var prompt: String?
    var onEditingChanged: ((Bool) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var searchField: ((NSSearchField) -> Void)?
    
    var imageKind: SearchFieldImage
    
    init(text: Binding<String>, prompt: String? = nil, onEditingChanged: ((Bool) -> Void)? = nil, onTextChanged: ((String) -> Void)? = nil, searchField: ((NSSearchField) -> Void)? = nil) {
        self._text = text
        self.prompt = prompt
        self.onEditingChanged = onEditingChanged
        self.onTextChanged = onTextChanged
        self.searchField = searchField
        
        self.imageKind = .search
    }
    
    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) {
            self.parent = parent
        }
        // Called when the text in the search field changes
        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
            parent.onTextChanged?(searchField.stringValue)
        }
        
        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }
        
        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
        }
    }

    func makeNSView(context: NSViewRepresentableContext<SearchField>) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        // Sets the coordinator as the search field's delegate
        searchField.delegate = context.coordinator
        searchField.placeholderString = prompt
        
        if self.imageKind == .filter, let cell = searchField.cell as? NSSearchFieldCell {
            cell.searchButtonCell?.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)
        }
        
        // Pass the NSSearchField instance to the external closure.
        self.searchField?(searchField)
        
        return searchField
    }
    
    func updateNSView(_ searchField: NSSearchField, context: NSViewRepresentableContext<SearchField>) {
        searchField.stringValue = text
        searchField.placeholderString = prompt
    }

    // Creates a coordinator instance to coordinate with the NSView
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}

enum SearchFieldImage {
    case search
    case filter
}

extension SearchField {
    func image(_ image: SearchFieldImage) -> SearchField {
        var view = self
        view.imageKind = image
        return view
    }
}
