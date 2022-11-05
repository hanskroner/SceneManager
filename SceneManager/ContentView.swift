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
    
    @StateObject var viewModel = deCONZClientModel()
    
    @State private var selected: SidebarItem?
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    Section("Groups") {
                        ForEach(viewModel.sidebarItems) { group in
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
            DetailView(item: $selected, showInspector: $showInspector)
                .navigationTitle(selected?.parentName ?? "Scene Manager")
                .navigationSubtitle(selected?.name ?? "")
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
    
    @Published private(set) var sidebarItems = [SidebarItem]()
    
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
        updatedSidebarItems = updatedSidebarItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        
        let list = updatedSidebarItems
        await MainActor.run {
            self.sidebarItems = list
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
