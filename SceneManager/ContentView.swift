//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    @SceneStorage("inspector") private var showInspector = false
    
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
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
                                                Button("Rename Scene") { }
                                                Button("Delete Scene") { }
                                            }
                                    }
                                } label: {
                                    Text(group.name)
                                        .contextMenu {
                                            Button("Rename Group") { }
                                            Button("Delete Group") {
                                                deleteGroup(group: group)
                                            }
                                        }
                                }
                            } else {
                                Text(group.name)
                                    .contextMenu {
                                        Button("Rename Group") { }
                                        Button("Delete Group") {
                                            deleteGroup(group: group)
                                        }
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
                        Button(action: {
                            Task {
                                await deconzModel.createNewGroup()
                            }
                        }) {
                            Label("", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .help("New Group")
                        
                        Spacer()
                    }
                    .padding([.leading, .bottom], 8)
                }
            }
        } detail: {
            DetailView(showInspector: $showInspector)
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
    
    func deleteGroup(group: SidebarItem) {
        Task {
            guard let groupID = group.groupID else { return }
            await deconzModel.deleteGroup(groupID: groupID)
        }
    }
}

struct SidebarItem: Identifiable, Hashable {
    let id: String
    var name: String
    var parentName: String?
    
    var children: [SidebarItem]?
    
    var groupID: Int?
    var sceneID: Int?
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
