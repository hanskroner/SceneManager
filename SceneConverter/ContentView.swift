//
//  ContentView.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        let strokeWidth: CGFloat = 4
        let radius: CGFloat = 15
        let dash: CGFloat = 10
        
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.gray, style: StrokeStyle(lineWidth: strokeWidth, dash: [dash]))
                .frame(width: 180, height: 180)
            
            VStack {
                Image(systemName: "document.badge.plus")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .imageScale(.large)
                    .foregroundStyle(.gray, .primary)
                    .foregroundStyle(.gray, .secondary)
                    .frame(width: 64)
                    .padding(.bottom, 14)
                
                Text("Drop file to convert")
                    .font(.title2)
                    .foregroundStyle(.gray, .primary)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
