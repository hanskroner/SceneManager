//
//  LightStateView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Views

struct LightStateView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("State")
                .font(.title2)
                .padding(.horizontal)
                .padding([.bottom], -4)
            
            SimpleJSONTextView(text: $deconzModel.jsonStateText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                .drop(if: (deconzModel.selectedSidebarItem?.type != .group) && (!deconzModel.selectedLightItems.isEmpty), types: [PresetItem.draggableType]) { providers in
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

// MARK: - Models

struct Dropable: ViewModifier {
    let condition: Bool
    
    let types: [UTType]
    let data: ([NSItemProvider]) -> Bool
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if condition {
            content.onDrop(of: types, isTargeted: nil, perform: data)
        } else {
            content
        }
    }
}

extension View {
    public func drop(if condition: Bool, types: [UTType], data: @escaping ([NSItemProvider]) -> Bool) -> some View {
        self.modifier(Dropable(condition: condition, types: types, data: data))
    }
}

// MARK: - Previews

struct LightStateView_Previews: PreviewProvider {
    static let deconzModel = SceneManagerModel()
    
    static var previews: some View {
        LightStateView()
            .environmentObject(deconzModel)
    }
}
