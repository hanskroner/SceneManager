//
//  Warning.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/04/2025.
//

import SwiftUI
import OSLog

struct WarningView: View {
    @Environment(WindowItem.self) private var window
    
    @Binding var showingPopover: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(window.warningTitle ?? "")
                .font(.headline)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
            
            Text(window.warningBody ?? "")
                .font(.callout)
                .fontDesign(.monospaced)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .fixedSize()
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(.ultraThickMaterial)
        .cornerRadius(8)
    }
}

#Preview {
    WarningView(showingPopover: .constant(true))
}
