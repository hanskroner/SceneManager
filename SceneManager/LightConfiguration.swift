//
//  LightConfiguration.swift
//  SceneManager
//
//  Created by Hans Kröner on 18/04/2025.
//

import SwiftUI
import deCONZ

struct LightConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var lightsConfiguration: [LightConfiguration] = []
    
    var filteredLightsConfiguration: [LightConfiguration] {
//        guard !filterText.isEmpty else { return lightsConfiguration }
        var displayConfigurations = lightsConfiguration
        
        // Sort
        displayConfigurations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        // Filter
//        displayConfigurations = displayConfigurations.filter {$0.name.localizedCaseInsensitiveContains(filterText)}

        return displayConfigurations
    }
    
    var body: some View {
        Text("Configuration Values")
        
        ScrollViewReader { scrollReader in
            List {
                ForEach(filteredLightsConfiguration, id: \.id) { light in
                    Text(light.name)
                }
            }
            // When inside a VStack, a List's size must be set explicitly
            .frame(idealHeight: 400, maxHeight: 600)
            .scrollBounceBehavior(.basedOnSize)
        }
        
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
        .task {
            lightsConfiguration = (try? await RESTModel.shared.lightConfigurations()) ?? []
        }
    }
}

//#Preview {
//    ConfigurationView(hueLights: .constant([
//        Light(lightId: 1, name: "Hue Light 1", state: LightState(), manufacturer: "Philips", modelId: "506313")
//    ]))
//}
