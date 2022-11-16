//
//  LightView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI

// MARK: - Models

struct LightItem: Identifiable, Hashable {
    let id: String
    var lightID: Int
    var name: String
    var state: String
}

// MARK: - Views

struct LightView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Lights")
                .font(.title2)
                .padding(.horizontal)
                .padding([.bottom], -4)
            
            List(deconzModel.lightsList, id: \.lightID, selection: $deconzModel.selectedLightItemIDs) { item in
                Text(item.name)
            }
            .onChange(of: deconzModel.selectedLightItemIDs) { newValue in
                deconzModel.jsonStateText = deconzModel.selectedLightItems.first?.state ?? ""
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LightBottomBarView()
            }
        }
        .frame(minWidth: 250)
    }
}

struct LightBottomBarView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    var body: some View {
        VStack {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(action: {
                    let window = NSWindow(
                        contentRect: .zero,
                        styleMask: [.titled, .closable],
                        backing: .buffered,
                        defer: false
                    )
                    
                    window.titlebarAppearsTransparent = true
                    
                    window.center()
                    window.isReleasedWhenClosed = false
                    
                    let view = AddLightView(window: window, deconzModel: deconzModel)
                        .padding()
                        .frame( width: 340, height: 400)
                    
                    let hosting = NSHostingView(rootView: view)
                    window.contentView = hosting
                    hosting.autoresizingMask = [.width, .height]
                    
                    NSApp.keyWindow?.beginSheet(window)
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Add Lights")
                .disabled(deconzModel.selectedSidebarItem == nil)
                
                Button(action: {
                    switch (deconzModel.selectedSidebarItem?.type) {
                    case .group:
                        Task {
                            let groupLightItems = deconzModel.lightsList.filter({ !deconzModel.selectedLightItems.contains($0) })
                            await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: groupLightItems)
                        }
                    case .scene:
                        Task {
                            // TODO: Find a nicer way to do this
                            // Set the Light's 'state' to 'REMOVE' to let 'modifySceneLights' this is a removal
                            let sceneLightItems = deconzModel.lightsList.map {
                                if (deconzModel.selectedLightItems.contains($0)) {
                                    var lightItem = $0
                                    lightItem.state = "REMOVE"
                                    return lightItem
                                } else {
                                    return $0
                                }
                            }
                            
                            await deconzModel.modifySceneLights(groupID: deconzModel.selectedSidebarItem!.groupID!, sceneID: deconzModel.selectedSidebarItem!.sceneID!, sceneLights: sceneLightItems)
                        }
                    default:
                        break
                    }
                }) {
                    Label("", systemImage: "minus")
                        .padding(.bottom, 4)
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Remove Lights")
                .disabled(deconzModel.selectedSidebarItem == nil ||
                          deconzModel.selectedLightItems.isEmpty)
                
                Spacer()
            }
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Previews

struct LightView_Previews: PreviewProvider {
    static let deconzModel = SceneManagerModel()
    
    static var previews: some View {
        LightView()
            .environmentObject(deconzModel)
    }
}
