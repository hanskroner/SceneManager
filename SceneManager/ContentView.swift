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

struct SceneList: Identifiable, Hashable {
    var id: String
    var name: String
    var children: [SceneList]?
}

struct ContentView: View {
    @State private var selected: SceneList?
    
    @SceneStorage("inspector") private var showInspector = false
    
    @State private var items: [SceneList] = [
        SceneList(id: "1", name: "Group 1", children: [
            SceneList(id: "11", name: "Scene 1", children: nil),
            SceneList(id: "12", name: "Scene 2", children: nil),
            SceneList(id: "13", name: "Scene 3", children: nil)
        ]),
        SceneList(id: "2", name: "Group 2", children: [
            SceneList(id: "21", name: "Scene 1", children: nil),
            SceneList(id: "22", name: "Scene 2", children: nil),
            SceneList(id: "23", name: "Scene 3", children: nil)
        ]),
        SceneList(id: "3", name: "Group 3", children: [
            SceneList(id: "31", name: "Scene 1", children: nil),
            SceneList(id: "32", name: "Scene 2", children: nil),
            SceneList(id: "33", name: "Scene 3", children: nil)
        ])
    ]
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    Section("Groups") {
                        ForEach(items) { group in
                            DisclosureGroup {
                                ForEach(group.children!) { item in
                                    NavigationLink(item.name, value: item)
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
                .navigationTitle("Group Name")
                .navigationSubtitle("Scene Name")
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
