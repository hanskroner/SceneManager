//
//  DetailView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct DetailView: View {
    @ObservedObject var deconzModel: deCONZClientModel
    
    @Binding var showInspector: Bool

    @State private var textEditor = ""
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Lights")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    List(deconzModel.sceneLights, id: \.self, selection: $deconzModel.selectedSceneLight) { item in
                        Text(item.name)
                    }
                    .onChange(of: deconzModel.selectedSceneLight) { newValue in
                        textEditor = deconzModel.selectedSceneLight?.state ?? ""
                    }
                }
                .frame(minWidth: 250)
                
                VStack(alignment: .leading) {
                    Text("State")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    SimpleJSONTextView(text: $textEditor, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                    
                    HStack {
                        Spacer()
                        Button("Apply to Group") {
                            Task { }
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        
                        Button("Apply to Selected") {
                            Task { }
                        }
                        .disabled(deconzModel.selectedSceneLight == nil)
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

struct SceneLight: Identifiable, Hashable {
    let id = UUID()
    var lightID: Int
    var name: String
    var state: String
}

//struct DetailView_Previews: PreviewProvider {
//    static var previews: some View {
//        DetailView(item: .constant(nil), deconzModel: nil, showInspector: .constant(false))
//    }
//}
