//
//  PresetDetails.swift
//  SceneManager
//
//  Created by Hans Kröner on 30/04/2025.
//

import SwiftUI

struct PresetDetails: View {
    let colorsXy = [
        color(fromXY: CGPoint(x: 0.1547, y: 0.1045)),
        color(fromXY: CGPoint(x: 0.1743, y: 0.1333)),
        color(fromXY: CGPoint(x: 0.2044, y: 0.1640)),
        color(fromXY: CGPoint(x: 0.2789, y: 0.2025)),
        color(fromXY: CGPoint(x: 0.4802, y: 0.3112))
    ]
    
    @State var droppersXy: [PickerDropper] = [
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.1547, y: 0.1045))), image: "E028-57384"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.1743, y: 0.1333))), image: "E028-57384"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.2044, y: 0.1640))), image: "E028-57384"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.2789, y: 0.2025))), image: "E028-57384"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.4802, y: 0.3112))), image: "E028-57384")
    ]
    
    @State var selectedDropperXy: PickerDropper?
    @State var brightnessXy: Double = 25.0
    
    // Sort the colors that make up the gradient so they are always displayed clockwise
    // by their hue values.
    private var sortedGradient: [NSColor] {
        // The gradient should start and end with the same color, but the same color
        // should not be passed in twice - copy the first color after sorting to the end
        // of the array
        var sorted = colorsXy.sorted(by: { $0.hueComponent < $1.hueComponent })
        if let first = sorted.first {
            sorted.append(first)
        }
        
        // To allow for some color selection range, colors get an
        // extra 5% saturation. Any more than this and the gradient
        // selector becomes inaccurate.
        return sorted.map { $0.adjust(saturation: 0.05) }
    }
    
    private var selectedColor: String {
        guard let selectedDropperXy else { return "no selection" }
        
        let xy = xy(fromColor: NSColor(selectedDropperXy.color))
        return "x: \(String(format: "%.6f", xy.x)), y: \(String(format: "%.6f", xy.y))"
    }
    
    var body: some View {
        Grid {
            GridRow {
                ColorGradientPickerView(gradient: sortedGradient, droppers: $droppersXy, selection: $selectedDropperXy)
                    .frame(width: 250, height: 250)
                    .padding(.top, 60)
                    .padding([.horizontal, .bottom], 30)
                
                BrightnessSlider(image: "E028-57384", sliderColor: selectedDropperXy?.color ?? .white, value: $brightnessXy)
                    .frame(width: 75, height: 300)
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
            }
            
            GridRow {
                Text("Selected \(selectedColor)")
                
                Text("Brightness: \(String(format: "%.0f", brightnessXy))%")
                    .padding(.vertical, 6)
            }
        }
    }
}

#Preview("Preset Details") {
    PresetDetails()
}
