//
//  AddPresetView.swift
//  SceneManager
//
//  Created by Hans Kröner on 22/11/2022.
//

import SwiftUI

// MARK: - Views

struct AddPresetView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @State private var newPresetName = ""
    
    @Binding var showingPopover: Bool
    
    private let decoder = JSONDecoder()
    
    var body: some View {
        VStack {
            Text("Give the current State a name to store it as a Preset")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 150, maxHeight: 40)
            
            TextField("Preset Name", text: $newPresetName)
                .frame(minWidth: 150)
            
            HStack {
                Spacer()
                Button("Store Preset") {
                    guard let lightState = try? decoder.decode(deCONZLightState.self, from: deconzModel.lightStateText.data(using: .utf8)!) else { return }
                    
                    // If a Preset with the same name already exits, overwrite its state
                    if let index = deconzModel.presets.firstIndex(where: { $0.name == newPresetName }) {
                        withAnimation {
                            deconzModel.presets[index].state = lightState
                            showingPopover = false
                        }
                        
                        do {
                            try deconzModel.savePresetItemToDocumentsDirectory(deconzModel.presets[index])
                        } catch {
                            print(error)
                        }
                    } else {
                        let newPresetItem = PresetItem(name: newPresetName, systemImage: "lightbulb.2", state: lightState)
                        
                        var presetItems = deconzModel.presets
                        presetItems.append(newPresetItem)
                        
                        withAnimation {
                            deconzModel.presets = presetItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                            showingPopover = false
                        }
                        
                        do {
                            try deconzModel.savePresetItemToDocumentsDirectory(newPresetItem)
                        } catch {
                            print(error)
                        }
                    }
                    
                    deconzModel.scrollToPresetItemID = newPresetName
                    newPresetName = ""
                }
                .disabled(newPresetName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding()
    }
}
