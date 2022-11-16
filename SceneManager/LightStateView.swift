//
//  LightStateView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI

// MARK: - Views

struct LightStateView: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("State")
                .font(.title2)
                .padding(.horizontal)
                .padding([.bottom], -4)
            
            SimpleJSONTextView(text: $deconzModel.jsonStateText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                .onDrop(of: [PresetItem.draggableType], isTargeted: nil) { providers in
                    // FIXME: Disallow drop when disabled
                    PresetItem.fromItemProviders(providers) { presets in
                        guard let first = presets.first else { return }
                        deconzModel.jsonStateText = first.preset.prettyPrint
                    }
                    
                    return true
                }
            
            HStack {
                Spacer()
                Button("Apply to Scene") {
                    Task {
                        await deconzModel.modifyScene(range: .allLightsInScene)
                    }
                }
                .disabled(deconzModel.selectedSidebarItem == nil
                          || deconzModel.jsonStateText.isEmpty)
                .fixedSize(horizontal: true, vertical: true)
                
                Button("Apply to Selected") {
                    Task {
                        await deconzModel.modifyScene(range: .selectedLightsOnly)
                    }
                }
                .disabled(deconzModel.selectedLightItems.isEmpty
                          || deconzModel.jsonStateText.isEmpty)
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(minWidth: 250)
        .padding(.bottom, 8)
        .disabled(deconzModel.selectedSidebarItem?.type == .group)
    }
}

// MARK: - Previews

struct LightStateView_Previews: PreviewProvider {
    static let deconzModel = deCONZClientModel()
    
    static var previews: some View {
        LightStateView()
            .environmentObject(deconzModel)
    }
}
