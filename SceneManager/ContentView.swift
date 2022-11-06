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
    
    var isRenaming: Bool = false
}

struct Sidebar: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $deconzModel.selectedSidebarItem) {
                Section("Groups") {
                    ForEach(deconzModel.sidebarItems, id: \.id) { group in
                        if let children = group.children {
                            DisclosureGroup {
                                ForEach(children, id: \.id) { scene in
                                    NavigationLink(value: scene) {
                                        SidebarItemView(item: scene)
                                    }
                                }
                            } label: {
                                SidebarItemView(item: group)
                            }
                        } else {
                            SidebarItemView(item: group)
                        }
                    }
                }
            }
            .frame(minWidth: 200)
            .listStyle(.sidebar)
            
            SidebarBottomBar()
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

struct SidebarItemView: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    @State var item: SidebarItem
    
    @FocusState private var isFocused: Bool
    
    @State var isPresentingConfirmation: Bool = false
    
    var body: some View {
        if (item.isRenaming) {
            HStack(spacing: 0) {
                TextField("", text: $item.name)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity)
                    .onChange(of: isFocused) { newValue in
                        if newValue == false {
                            item.isRenaming = false
                            Task {
                                await deconzModel.renameGroup(groupID: item.groupID!, name: item.name)
                            }
                        }
                    }
                    .padding([.leading], -8)
            }
        } else {
            Text(item.name)
                .contextMenu {
                    Button(action: {
                        item.isRenaming = true
                        isFocused = true
                    }, label: {
                        if (item.sceneID == nil) {
                            Text("Rename Group")
                        } else {
                            Text("Rename Scene")
                        }
                    })
                    
                    Button(action: {
                        isPresentingConfirmation = true
                    }, label: {
                        if (item.sceneID == nil) {
                            Text("Delete Group")
                        } else {
                            Text("Delete Scene")
                        }
                    })
                }
                .confirmationDialog("Are you sure you want to delete '\(item.name)'?", isPresented: $isPresentingConfirmation) {
                    if (item.sceneID == nil) {
                        Button("Delete Group", role: .destructive) {
                            deleteGroup(group: item)
                        }
                    } else {
                        Button("Delete Scene", role: .destructive) {
//                            deleteScene(scene: item)
                        }
                    }
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
