//
//  EditableText.swift
//  SceneManager
//
//  Created by Hans Kröner on 26/04/2025.
//

import SwiftUI

// MARK: - EditableText View

struct EditableText: View {
    @Binding var text: String
    @Binding var hasFocus: Bool
    @Binding var isRenaming: Bool
    
    @State private var editingText: String
    @FocusState private var isFocused: Bool
    
    init(text: Binding<String>, hasFocus: Binding<Bool>, isRenaming: Binding<Bool>) {
        self._text = text
        self._hasFocus = hasFocus
        self._isRenaming = isRenaming
        self.editingText = text.wrappedValue
    }
    
    var body: some View {
        TextField("", text: $editingText)
            .focused($isFocused, equals: true)
            .onSubmit(of: .text) {
                text = editingText
            }
            .onExitCommand {
                editingText = text
                isRenaming = false
            }
            .onChange(of: isFocused) { previousValue, newValue in
                // Send the focus back to the parent
                hasFocus = newValue
            }
            .onChange(of: hasFocus) { previousValue, newValue in
                // Update the focus if it is set externally
                if (newValue == true && isFocused == false) {
                    isFocused = true
                }
                
                if (newValue == false && isFocused == true) {
                    isFocused = false
                }
            }
    }
}

