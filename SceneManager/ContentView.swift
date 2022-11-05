//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("deconz_url") private var url = ""
    @AppStorage("deconz_key") private var key = ""
    
    private enum Tabs: Hashable {
        case deconz
    }
    
    var body: some View {
        TabView {
            Grid(alignment: .trailing) {
                GridRow {
                    Spacer()
                    Text("deCONZ URL:")
                    TextField("http://127.0.0.1:8080", text: $url)
                }
                
                GridRow {
                    Spacer()
                    Text("deCONZ API Key:")
                    TextField("ABCDEF1234", text: $key)
                }
            }
            .tabItem {
                Label("deCONZ", systemImage: "network")
            }
            .tag(Tabs.deconz)
        }
        .padding()
        .frame(width: 375, height: 100)
    }
}

struct ContentView: View {
    @SceneStorage("inspector") private var showInspector = false
    
    @StateObject var deconzModel = deCONZClientModel()
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $deconzModel.selectedSidebarItem) {
                    Section("Groups") {
                        ForEach(deconzModel.sidebarItems) { group in
                            if let children = group.children {
                                DisclosureGroup {
                                    ForEach(children) { scene in
                                        NavigationLink(scene.name, value: scene)
                                            .contextMenu {
                                                Button(action: { }, label: {
                                                    Text("Rename Scene")
                                                })
                                                Button(action: { }, label: {
                                                    Text("Delete Scene")
                                                })
                                            }
                                    }
                                } label: {
                                    Text(group.name)
                                        .contextMenu {
                                            Button(action: { }, label: {
                                                Text("Rename Group")
                                            })
                                            Button(action: { }, label: {
                                                Text("Delete Group")
                                            })
                                        }
                                }
                            } else {
                                Text(group.name)
                                    .contextMenu {
                                        Button(action: { }, label: {
                                            Text("Rename Group")
                                        })
                                        Button(action: { }, label: {
                                            Text("Delete Group")
                                        })
                                    }
                            }
                        }
                    }
                }
                .frame(minWidth: 200)
                .listStyle(.sidebar)
                VStack {
                    Divider()
                    HStack {
                        Menu {
                            Button(action: { }, label: {
                                Text("New Group")
                            })
                            Button(action: { }, label: {
                                Text("New Scene")
                            })
                        } label: {
                            Label("", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()

                        Spacer()
                    }
                    .padding([.leading, .bottom], 8)
                }
            }
        } detail: {
            DetailView(deconzModel: deconzModel, showInspector: $showInspector)
                .navigationTitle(deconzModel.selectedSidebarItem?.parentName ?? "Scene Manager")
                .navigationSubtitle(deconzModel.selectedSidebarItem?.name ?? "No Scene Selected")
        }
        .frame(minWidth: 960, minHeight: 300)
        .background(Color(NSColor.gridColor))
        .toolbar {
            Button(action: { withAnimation { showInspector.toggle() }}) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

struct SidebarItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var parentName: String?
    
    var children: [SidebarItem]?
    
    var groupID: Int?
    var sceneID: Int?
}

class deCONZClientModel: ObservableObject {
    private let deconzClient = deCONZClient()
    
    private let encoder = JSONEncoder()
    
    @Published var selectedSidebarItem: SidebarItem? = nil {
        didSet {
            self.selectedSceneLight = nil
            
            if (selectedSidebarItem == nil) {
                Task {
                    await MainActor.run {
                        self.sceneLights = [SceneLight]()
                    }
                }
            }
            
            if let groupID = selectedSidebarItem?.groupID, let sceneID = selectedSidebarItem?.sceneID {
                Task {
                    await self.updateSceneLights(forGroupID: groupID, sceneID: sceneID)
                }
            }
        }
    }
    
    @Published var selectedSceneLight: SceneLight? = nil
    
    @Published private(set) var sidebarItems = [SidebarItem]()
    @Published private(set) var sceneLights = [SceneLight]()
    
    private var cacheLights: [Int: deCONZLight]?
    private var cacheGroups: [Int: deCONZGroup]?
    private var cacheScenes: [Int: [Int: deCONZScene]]?
    
    init() {
        Task {
            self.cacheLights = try await deconzClient.getAllLights()
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
            
            Task {
                await refreshSidebarItems()
            }
        }
    }
    
    private func refreshSidebarItems() async {
        var updatedSidebarItems = [SidebarItem]()
        
        guard let cacheGroups = self.cacheGroups,
              let cacheScenes = self.cacheScenes else { return }
        
        // Ignore Groups where 'devicemembership' is not empty
        // These groups are created by switches or sensors and are not the kind we're looking for.
        let filteredGroups = cacheGroups.filter({ $0.value.devicemembership?.isEmpty ?? true })
        
        for (_, group) in filteredGroups {
            guard let groupName = group.name,
                  let groupStringID = group.id,
                  let groupID = Int(groupStringID),
                  let scenes = group.scenes
            else { return }
            
            var groupItem = SidebarItem(name: groupName, groupID: groupID)
            
            for (sceneStringID) in scenes {
                guard let sceneID = Int(sceneStringID),
                      let sceneName = cacheScenes[groupID]?[sceneID]?.name
                else { return }
                
                let sceneItem = SidebarItem(name: sceneName, parentName: groupName, groupID: groupID, sceneID: sceneID)
                
                if (groupItem.children == nil) {
                    groupItem.children = [SidebarItem]()
                }
                
                groupItem.children!.append(sceneItem)
            }
            
            // Sort Scene names alphabetically
            groupItem.children = groupItem.children?.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            updatedSidebarItems.append(groupItem)
        }
        
        // Sort Group names alphabetically
        let list = updatedSidebarItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.sidebarItems = list
        }
    }
    
    func updateSceneLights(forGroupID groupID: Int, sceneID: Int) async {
        var updatedSceneLights = [SceneLight]()
        
        let sceneAttributes = try? await deconzClient.getSceneAttributes(groupID: groupID, sceneID: sceneID)
        
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let sceneAttributes = sceneAttributes
        else { return }
        
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        
        for (stringLightID) in cacheGroups[groupID]?.lights ?? [] {
            guard let lightID = Int(stringLightID),
                  let light = cacheLights[lightID],
                  let lightName = light.name,
                  let lightState = sceneAttributes[lightID]
            else { return }
            
            let stateString = lightState.prettyPrint
            updatedSceneLights.append(SceneLight(lightID: lightID, name: lightName, state: stateString))
        }
        
        // Sort Light names alphabetically
        let list = updatedSceneLights.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.sceneLights = list
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
