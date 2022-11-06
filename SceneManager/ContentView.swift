//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    @SceneStorage("inspector") private var showInspector = false
    
    var body: some View {
        NavigationSplitView {
            Sidebar()
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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

struct Sidebar: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    @State var isPresentingConfirmDeleteGroup: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $deconzModel.selectedSidebarItem) {
                Section("Groups") {
                    ForEach(deconzModel.sidebarItems, id: \.id) { group in
                        if let children = group.children {
                            DisclosureGroup {
                                ForEach(children, id: \.id) { scene in
                                    NavigationLink(scene.name, value: scene)
                                        .contextMenu {
                                            Button("Rename Scene") { }
                                            Button("Delete Scene") { }
                                        }
                                }
                            } label: {
                                TextGroupWithContextMenu(item: group, isPresentingConfirmation: $isPresentingConfirmDeleteGroup)
                            }
                        } else {
                            TextGroupWithContextMenu(item: group, isPresentingConfirmation: $isPresentingConfirmDeleteGroup)
                                .confirmationDialog("Are you sure you want to delete the Group '\(group.name)'?", isPresented: $isPresentingConfirmDeleteGroup) {
                                    Button("Delete Group", role: .destructive) {
                                        deleteGroup(group: group)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(minWidth: 200)
            .listStyle(.sidebar)
            
            SidebarBottomBar()
        }
    }
    
    func deleteGroup(group: SidebarItem) {
        Task {
            guard let groupID = group.groupID else { return }
            await deconzModel.deleteGroup(groupID: groupID)
        }
    }
}

struct SidebarBottomBar: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    var body: some View {
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
}

struct TextGroupWithContextMenu: View {
    var item: SidebarItem
    
    @Binding var isPresentingConfirmation: Bool
    
    var body: some View {
        Text(item.name)
            .contextMenu {
                Button("Rename Group") { }
                
                Button("Delete Group") {
                    isPresentingConfirmation = true
                }
            }
    }
}
