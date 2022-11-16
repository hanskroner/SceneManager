//
//  AddLightsView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI

// MARK: - Views

struct AddLightView: View {
    let window: NSWindow
    let deconzModel: SceneManagerModel
    
    @State var lightItems = [LightItem]()
    @State var addLightItems = Set<LightItem>()
    
    func loadLightItems() async {
        var lightItems: [LightItem]
        switch deconzModel.selectedSidebarItem?.type {
        case .group:
            lightItems = deconzModel.lightsNotIn(groupID: deconzModel.selectedSidebarItem!.groupID!)
        case .scene:
            lightItems = await deconzModel.lightsIn(groupID: deconzModel.selectedSidebarItem!.groupID!, butNotIn: deconzModel.selectedSidebarItem!.sceneID!)
        default:
            lightItems = []
        }
        
        self.lightItems = lightItems
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image("Icon")
                    .resizable()
                    .frame(width: 72, height: 72)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Lights to '\(deconzModel.selectedSidebarItem?.name ?? "")'")
                        .font(.system(.headline))
                }
                .padding(.top, 6)
            }
            
            List(lightItems, id: \.self, selection: $addLightItems) { item in
                Text(item.name)
            }
            .task {
                await loadLightItems()
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    window.close()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("Add \(addLightItems.count == 1 ? "Light" : "Lights")") {
                    var lightItems = deconzModel.lightsList
                    
                    Task {
                        if (deconzModel.selectedSidebarItem!.type == .group) {
                            lightItems.append(contentsOf: addLightItems)
                            await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: lightItems)
                        } else if (deconzModel.selectedSidebarItem!.type == .scene) {
                            // TODO: Find a nicer way to do this
                            // Set the Light's 'state' to 'ADD' to let 'modifySceneLights' this is an addition
                            let modifiedLightItems = addLightItems.map {
                                var lightItem = $0
                                lightItem.state = "ADD"
                                return lightItem
                            }
                            
                            lightItems.append(contentsOf: modifiedLightItems)
                            await deconzModel.modifySceneLights(groupID: deconzModel.selectedSidebarItem!.groupID!, sceneID: deconzModel.selectedSidebarItem!.sceneID!, sceneLights: lightItems)
                        }
                        
                        window.close()
                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(addLightItems.isEmpty)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Previews

struct AddLightView_Previews: PreviewProvider {
    static let deconzModel = SceneManagerModel()
    
    static var previews: some View {
        // FIXME: Contains implicitly unwrapped Optionals that will be 'nil' in the Preview
        AddLightView(window: NSWindow(), deconzModel: deconzModel)
    }
}
