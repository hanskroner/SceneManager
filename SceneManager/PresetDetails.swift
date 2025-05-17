//
//  PresetDetails.swift
//  SceneManager
//
//  Created by Hans Kröner on 30/04/2025.
//

import SwiftUI

struct PresetDetails: View {
    
    // MARK: colorXy
    
    let colorsXy = [
        color(fromXY: CGPoint(x: 0.6400, y: 0.3300)),   // sRGB (red)
        color(fromXY: CGPoint(x: 0.4200, y: 0.5050)),   // sRGB (yellow)
        color(fromXY: CGPoint(x: 0.3000, y: 0.6000)),   // sRGB (green)
        color(fromXY: CGPoint(x: 0.2250, y: 0.3300)),   // sRGB (cyan)
        color(fromXY: CGPoint(x: 0.1500, y: 0.0600)),   // sRGB (blue)
        color(fromXY: CGPoint(x: 0.3200, y: 0.1550))    // sRGB (magenta)
    ]
    
    private var sortedColorsXy: [NSColor] {
        var sorted = colorsXy.sorted(by: { $0.hueComponent < $1.hueComponent })
        if let first = sorted.first {
            sorted.append(first)
        }
        
        // Completely saturate the colors to house the full spectrum in the picker.
        return sorted.map { NSColor(calibratedHue: $0.hueComponent, saturation: 1.0, brightness: $0.brightnessComponent, alpha: 1.0).usingColorSpace(.sRGB)! }
    }
    
    @State var droppersColor: [PickerDropper] = [
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.1547, y: 0.1045))), image: "e27-a60"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.1743, y: 0.1333))), image: "e27-a60"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.2044, y: 0.1640))), image: "e27-a60"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.2789, y: 0.2025))), image: "e27-a60"),
        PickerDropper(color: Color(nsColor: color(fromXY: CGPoint(x: 0.4802, y: 0.3112))), image: "e27-a60")
        ]
    
    @State var selectedDropperColor: PickerDropper?
    
    let colorsScene = [
        color(fromXY: CGPoint(x: 0.1547, y: 0.1045)),
        color(fromXY: CGPoint(x: 0.1743, y: 0.1333)),
        color(fromXY: CGPoint(x: 0.2044, y: 0.1640)),
        color(fromXY: CGPoint(x: 0.2789, y: 0.2025)),
        color(fromXY: CGPoint(x: 0.4802, y: 0.3112))
    ]
    
    // Sort the colors that make up the gradient so they are always displayed clockwise
    // by their hue values.
    private var sortedGradient: [NSColor] {
        // The gradient should start and end with the same color, but the same color
        // should not be passed in twice - copy the first color after sorting to the end
        // of the array
        var sorted = colorsScene.sorted(by: { $0.hueComponent < $1.hueComponent })
        if let first = sorted.first {
            sorted.append(first)
        }
        
        // To allow for some color selection range, colors get an
        // extra 5% saturation. Any more than this and the gradient
        // selector becomes inaccurate.
        return sorted.map { $0.adjust(saturation: 0.05).usingColorSpace(.sRGB)! }
    }
    
    private var selectedColor: String {
        guard let selectedDropperColor else { return "no selection" }
        
        let xy = xy(fromColor: NSColor(selectedDropperColor.color))
        return "x: \(String(format: "%.6f", xy.x)), y: \(String(format: "%.6f", xy.y))"
    }
    
    // MARK: colorCt
    
    let colorsCt = [
        color(fromMired: 550)!,
        color(fromMired: 400)!,
        color(fromMired: 300)!,
        color(fromMired: 200)!,
        color(fromMired: 175)!,
        color(fromMired: 150)!,
        color(fromMired: 110)!
    ]
    
    @State var droppersCt: [PickerDropper] = [
        PickerDropper(color: Color(color(fromMired: 255)!), image: "e27-a60")
    ]
    
    @State var selectedDropperCt: PickerDropper?
    
    var selectedMireds: String {
        guard let selectedDropperCt else { return "no selection" }
        
        return String(mired(fromColor: NSColor(selectedDropperCt.color)))
    }
    
    // MARK: TabView
    
    enum PickerTab: Hashable {
        case colorXy
        case colorCt
        case colorScene
    }
    
    @State private var selectedPickerTab: PickerTab = .colorScene
    
    @State var brightness: Double = 25.0
    
    // MARK: View Body
    
    var body: some View {
        Grid {
            GridRow(alignment: .bottom) {
                TabView(selection: $selectedPickerTab) {
                    ColorGradientPickerView(gradient: sortedColorsXy, droppers: $droppersColor, selection: $selectedDropperColor)
                        .frame(width: 250, height: 250)
                        .tabItem {
                            Text("Color XY")
                        }
                        .tag(PickerTab.colorXy)
                    
                    ColorTemperaturePickerView(gradient: colorsCt, droppers: $droppersCt, selection: $selectedDropperCt)
                        .frame(width: 250, height: 250)
                        .tabItem {
                            Text("Color CT")
                        }
                        .tag(PickerTab.colorCt)
                    
                    ColorGradientPickerView(gradient: sortedGradient, droppers: $droppersColor, selection: $selectedDropperColor)
                        .frame(width: 250, height: 250)
                        .tabItem {
                            Text("Color Scene")
                        }
                        .tag(PickerTab.colorScene)
                }
                .padding(.top, 30)
                
                BrightnessSlider(image: "e27-a60", sliderColor: selectedDropperColor?.color ?? selectedDropperCt?.color ?? .white, value: $brightness)
                    .frame(width: 75, height: 250)
            }
            
            GridRow {
                Text("Selected \(selectedColor)")
                
                Text("Brightness: \(String(format: "%.0f", brightness))%")
                    .frame(width: 110)
                    .fixedSize()
                    .padding(.vertical, 6)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Preset Details") {
    PresetDetails()
        .frame(width: 400)
}
