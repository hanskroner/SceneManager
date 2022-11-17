//
//  DetailView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @Binding var showInspector: Bool
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                LightView()
                
                LightStateView()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if (showInspector) {
                PresetView()
                .frame(minWidth: 200, maxWidth: 200, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: - Previews

struct DetailView_Previews: PreviewProvider {
    static let deconzModel = SceneManagerModel()
    
    static var previews: some View {
        DetailView(showInspector: .constant(false))
            .environmentObject(deconzModel)
    }
}
