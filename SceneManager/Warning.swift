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
                .textSelection(.enabled)
                .font(.headline)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
            
            ScrollView {
                Text(window.warningBody ?? "")
                    .textSelection(.enabled)
                    .font(.callout)
                    .fontDesign(.monospaced)
            }
            // FIXME: Seems broken in macOS 15.4
            //        Scrollbar won't bounce even if the content is big enough for it to.
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 340, maxHeight: 160, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .padding(.leading, 14)
        .background(.ultraThickMaterial)
        .cornerRadius(8)
    }
}

#Preview("Short Error") {
    let window = WindowItem()
    
    WarningView(showingPopover: .constant(true))
        .padding(4)
        .background(Color.yellow.padding(-80))
        .environment(window)
        .task {
            window.warningTitle = "deCONZ REST API Error"
            window.warningBody = """
                address: /lights/8/config/bri/couple_ct
                description: parameter, couple_ct, not available
                """
        }
        .frame(width: 370, height: 300)
}

#Preview("Long Error") {
    let window = WindowItem()
    
    WarningView(showingPopover: .constant(true))
        .padding(4)
        .background(Color.yellow.padding(-80))
        .environment(window)
        .task {
            window.warningTitle = "deCONZ REST API Error"
            window.warningBody = """
                address: /lights/8/config/bri/couple_ct
                description: parameter, couple_ct, not available

                address: /lights/8/config/bri/execute_if_off
                description: parameter, execute_if_off, not available

                address: /lights/8/config/color/execute_if_off
                description: parameter, execute_if_off, not available
                
                address: /lights/8/config/bri/couple_ct
                description: parameter, couple_ct, not available

                address: /lights/8/config/bri/execute_if_off
                description: parameter, execute_if_off, not available

                address: /lights/8/config/color/execute_if_off
                description: parameter, execute_if_off, not available
                """
        }
        .frame(width: 370, height: 300)
}
