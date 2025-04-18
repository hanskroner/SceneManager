//
//  StartupConfiguration.swift
//  SceneManager
//
//  Created by Hans Kröner on 18/04/2025.
//

import SwiftUI

struct StartupConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Text("Startup Configuration Values")
        
        HStack {
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .fixedSize()
            .keyboardShortcut(.cancelAction)
            
            Button("Apply Configuration") {
                
            }
            .fixedSize()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
    }
}

#Preview {
    StartupConfigurationView()
}
