//
//  DetailView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct LightList: Identifiable, Hashable {
    var id: String
    var name: String
}

struct DetailView: View {
    @Binding var item: SceneList?
    @Binding var showInspector: Bool
    
    @State private var textEditor = ""
    
    @State private var selected: LightList?
    
    @State private var lights: [LightList] = [
        LightList(id: "1", name: "Light 1"),
        LightList(id: "2", name: "Light 2"),
        LightList(id: "3", name: "Light 3")
    ]
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Lights")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    List(lights, id: \.self, selection: $selected) { item in
                        Text(item.name)
                    }
                }
                .frame(minWidth: 250)
                
                VStack(alignment: .leading) {
                    Text("State")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    TextEditor(text: $textEditor)
                        .font(.system(size: 12, design: .monospaced))
                    
                    HStack {
                        Spacer()
                        Button("Apply to Group") {
                            Task { }
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        
                        Button("Apply to Selected") {
                            Task { }
                        }
                        .disabled(selected == nil)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .frame(minWidth: 250)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if (showInspector) {
                Text("Inspector")
                    .frame(minWidth: 200, maxWidth: 200, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .trailing))
            }
        }
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        DetailView(item: .constant(nil), showInspector: .constant(false))
    }
}
