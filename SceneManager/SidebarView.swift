//
//  SidebarView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI

// MARK: - Models

struct SidebarItem: Identifiable, Hashable {
    enum SidebarItemType {
        case blank
        case group
        case scene
    }
    
    let id: String
    var name: String
    var parentName: String?
    
    var children: [SidebarItem]?
    
    var groupID: Int?
    var sceneID: Int?
    
    var isRenaming: Bool = false
    var isExpanded: Bool = false
    var wantsFocus: Bool = false
    
    var type: SidebarItemType {
        if ((groupID != nil) && (sceneID == nil)) { return .group }
        if ((groupID != nil) && (sceneID != nil)) { return .scene }
        
        return .blank
    }
    
    var groupName: String? {
        switch self.type {
        case .blank: return nil
        case .group: return self.name
        case .scene: return self.parentName
        }
    }
    
    var sceneName: String? {
        switch self.type {
        case .scene: return self.name
        default: return nil
        }
    }
}

// MARK: - Views

struct SidebarView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    var body: some View {
        ScrollViewReader { scrollReader in
            List(selection: $deconzModel.selectedSidebarItemID) {
                Section("Groups") {
                    ForEach(Array(deconzModel.sidebarItems.enumerated()), id: \.1.id) { i, group in
                        if let children = group.children {
                            DisclosureGroup(isExpanded: $deconzModel.sidebarItems[i].isExpanded) {
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
                
                // 'safeAreaInsets' doesn't seem to allow bottom bar's ultra-thin material to do anything.
                // Instead, this spacer acts as the inset and the bottom bar is drawn in an overlay.
                Spacer()
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                SidebarBottomBarView()
            }
            
            .frame(minWidth: 200)
            .listStyle(.sidebar)
            .onChange(of: deconzModel.scrollToSidebarItemID) { item in
                if let item = item {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                    deconzModel.removeListSnapshot()
                }
            }
        }
    }
}

struct SidebarBottomBarView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                Button(action: {
                    Task {
                        await deconzModel.createNewSidebarItem(groupID: nil, sceneID: nil)
                    }
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("New Group")
                
                Spacer()
            }
            .background(.ultraThinMaterial)
        }
    }
}

struct SidebarItemView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @State var item: SidebarItem
    
    @FocusState private var isFocused: Bool
    
    @State var isPresentingConfirmation: Bool = false
    
    var body: some View {
        if (item.isRenaming) {
            TextField("", text: $item.name)
                .focused($isFocused)
                .frame(maxWidth: .infinity)
                .onChange(of: isFocused) { newValue in
                    if newValue == false {
                        item.isRenaming = false
                        
                        Task {
                            if ((item.groupID == -999) && (item.sceneID == -999)) {
                                await deconzModel.createGroup(name: item.name)
                            } else if ((item.groupID != -999) && (item.sceneID == -999)) {
                                await deconzModel.createScene(groupID: item.groupID!, name: item.name)
                            } else if ((item.groupID != nil) && (item.sceneID == nil)) {
                                await deconzModel.renameGroup(groupID: item.groupID!, name: item.name)
                            } else {
                                await deconzModel.renameScene(groupID: item.groupID!, sceneID: item.sceneID!, name: item.name)
                            }
                        }
                    }
                }
                .onAppear {
                    isFocused = item.wantsFocus
                }
                .padding([.leading], -8)
        } else {
            Text(item.name)
                .contextMenu {
                    if (item.sceneID == nil) {
                        Button(action: {
                            Task {
                                await deconzModel.createNewSidebarItem(groupID: item.groupID, sceneID: nil)
                            }
                        }, label: {
                            Text("New Scene")
                        })
                    }
                    
                    Button(action: {
                        item.isRenaming = true
                        item.wantsFocus = true
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
                            deleteGroup(item)
                        }
                    } else {
                        Button("Delete Scene", role: .destructive) {
                            deleteScene(item)
                        }
                    }
                }
        }
    }
    
    func deleteGroup(_ group: SidebarItem) {
        Task {
            guard let groupID = group.groupID else { return }
            await deconzModel.deleteGroup(groupID: groupID)
        }
    }
    
    func deleteScene(_ scene: SidebarItem) {
        Task {
            guard let groupID = scene.groupID,
                  let sceneID = scene.sceneID
            else { return }
            
            await deconzModel.deleteScene(groupID: groupID, sceneID: sceneID)
        }
    }
}

// MARK: - Previews

struct SidebarView_Previews: PreviewProvider {
    static let deconzModel = SceneManagerModel()
    
    static var previews: some View {
        SidebarView()
            .environmentObject(deconzModel)
    }
}
