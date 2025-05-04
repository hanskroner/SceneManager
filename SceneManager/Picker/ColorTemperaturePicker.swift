//
//  ColorTemperaturePicker.swift
//  SceneManager
//
//  Created by Hans Kröner on 12/04/2025.
//

import SwiftUI
import simd
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.picker", category: "temperature-picker")

struct ColorTemperaturePickerView: View {
    let gradient: [NSColor]
    
    @Binding var droppers: [PickerDropper]
    @Binding var selection: PickerDropper?
    
    @State private var size: CGFloat = 0.0
    @State private var transitions: [Transition] = []
    
    private struct Transition {
        let fromLocation: Double
        let toLocation: Double
        let fromColor: NSColor
        let toColor: NSColor

        func color(forPercent percent: Double) -> NSColor {
            // Linear interpolation in RGB
            let red = fromColor.redComponent + percent * (toColor.redComponent - fromColor.redComponent)
            let green = fromColor.greenComponent + percent * (toColor.greenComponent - fromColor.greenComponent)
            let blue = fromColor.blueComponent + percent * (toColor.blueComponent - fromColor.blueComponent)
            let alpha = fromColor.alphaComponent + percent * (toColor.alphaComponent - fromColor.alphaComponent)
            
            return NSColor(red: red,
                           green: green,
                           blue: blue,
                           alpha: alpha)
        }
    }
    
    init(gradient: [NSColor], droppers: Binding<[PickerDropper]>, selection: Binding<PickerDropper?> = .constant(nil)) {
        self.gradient = gradient
        self._droppers = droppers
        self._selection = selection
    }
    
    // MARK: Body
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base linear gradient circle
            Circle()
                .fill(
                    LinearGradient(colors: gradient.map({ Color(nsColor: $0) }), startPoint: .top, endPoint: .bottom)
                )
            
            // Blurred linear gradient to smooth color transitions
            Circle()
                .fill(
                    LinearGradient(colors: gradient.map({ Color(nsColor: $0) }), startPoint: .top, endPoint: .bottom)
                )
                .blur(radius: 20)
                .clipShape(Circle())
                // TODO: Consider making a parameter
                .brightness(-0.08)
            
            // Draw color picker droppers
            ForEach($droppers, id: \.id) { $dropper in
                let dragGesture = DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Only select the dropper on a click - once the dropper
                        // starts getting dragged around, it'll jump so it's bottom
                        // tip is anchored to the mouse cursor.
                        if value.location == value.startLocation {
                            // Deselect previously selected dropper
                            if let selection,
                               selection.id != dropper.id {
                                selection.isSelected = false
                            }
                            
                            // Select this dropper
                            if !dropper.isSelected {
                                selection = dropper
                                dropper.isSelected = true
                            }
                            
                            return
                        }
                        
                        dropper.location = value.location
                        dropper.isDragging = true
                    }
                    .onEnded { _ in
                        dropper.isDragging = false
                    }
                
                PickerDropperView(dropper: $dropper)
                    .onLocationChanged {
                        do {
                            dropper.color = try colorAt(dropper.location)
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            dropper.color = .black
                        }
                    }
                    .frame(height: size * 0.16)
                    .offset(x: 0, y: -size * 0.08)
                    .position(constrainToBounds(dropper.location))
                    .gesture(dragGesture)
                    .task {
                        do {
                            dropper.location = try locationFor(color: NSColor(dropper.color))
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            dropper.location = .zero
                        }
                    }
            }
        }
        .compositingGroup()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: {  size in
            self.size = size.height > size.width ? size.width : size.height
        }
        .onTapGesture {
            if let selection {
                selection.isSelected = false
                self.selection = nil
            }
        }
    }
    
    // MARK: Private Methods
    
    private func loadTransitions() {
        transitions.removeAll()
        
        if gradient.count > 1 {
            let transitionsCount = gradient.count - 1
            let locationStep = 1.0 / Double(transitionsCount)
            
            for i in 0 ..< transitionsCount {
                let fromLocation, toLocation: Double
                let fromColor, toColor: NSColor
                
                fromLocation = locationStep * Double(i)
                toLocation = locationStep * Double(i + 1)
                
                fromColor = gradient[i]
                toColor = gradient[i + 1]
                
                let transition = Transition(fromLocation: fromLocation, toLocation: toLocation,
                                            fromColor: fromColor, toColor: toColor)
                transitions.append(transition)
            }
        }
    }
    
    private func color(forY y: Double) throws -> NSColor {
        if self.transitions.isEmpty { loadTransitions() }
        
        // Convert the percentage, which is a percentage of the overall gradient, to a
        // percentage relative to the transition where the color is located and obtain the
        // color at that location.
        let percent = y.convert(fromZeroToMax: size, toZeroToMax: 1.0)

        guard let transition = transition(forPercent: percent) else { throw GradientError.percentNotInGradient(percent: percent) }

        let normalizedPercent = percent.convert(fromMin: transition.fromLocation,
                                                max: transition.toLocation,
                                                toMin: 0.0,
                                                max: 1.0)
        
        return transition.color(forPercent: normalizedPercent)
    }
    
    private func transition(forPercent percent: Double) -> Transition? {
        let filtered = transitions.filter { percent >= $0.fromLocation && percent < $0.toLocation }
        let defaultTransition = percent <= 0.5 ? transitions.first : transitions.last
        
        return filtered.first ?? defaultTransition
    }
    
    private func constrainToBounds(_ location: CGPoint) -> CGPoint {
        let origin = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2
        let distance = CGFloat(sqrt(pow(location.x - origin.x, 2) + pow(location.y - origin.y, 2)))
        
        // Is location out of bounds?
        if distance > radius {
            let hypot = distance - radius
            let angle = atan2(location.y - origin.y, location.x - origin.x)
            
            let moveX = location.x - (hypot * cos(angle))
            let moveY = location.y - (hypot * sin(angle))
            
            return CGPoint(x: moveX, y: moveY)
        }
        
        return location
    }
    
    private func closestColor(inTransition transition: Transition, toColor color: NSColor) -> NSColor {
        // The passed-in color might not exist exactly in the transition. The challenge
        // becomes how to determine which color that does exist in the transition is
        // closest to the passed-in one. To do this, we will imagine the RGB components of
        // the colors at the extremes of the transition as points in 3D space and draw a
        // line between them. The passed-in color will also be a point in that 3D space,
        // likely close to that line. To pick to closests color, we project the point onto
        // the line using the shortest posible distance. The closest color will be at the
        // point where the projected point and the line intersect.
        
        // Point 'A' represents that starting color of the transition, and point 'B'
        // represents the end color. Together, they create the line segment 'AB' onto
        // which point 'C' - which represents the passed-in color - will be projected.
        // Use SIMD for 3D Vector math
        let A = SIMD3(Float(transition.fromColor.redComponent),
                      Float(transition.fromColor.greenComponent),
                      Float(transition.fromColor.blueComponent))
        let B = SIMD3(Float(transition.toColor.redComponent),
                      Float(transition.toColor.greenComponent),
                      Float(transition.toColor.blueComponent))
        let C = SIMD3(Float(color.redComponent),
                      Float(color.greenComponent),
                      Float(color.blueComponent))
        
        // 'B' minus 'A' (BmA) and 'C' minus 'A' (CmA) are two vectors that represent the
        // direction from 'B' to 'A' and 'C' to 'A' respectively. They can be throught of
        // as two sides of a triangle, where the third side is made of of the projection
        // of 'C' onto 'AB' and is perpendicular to 'AB'.
        // 'D' is what we're looking for: the a point on 'AB' that is closests to 'C'.
        let BmA = B - A
        let CmA = C - A
        let t = dot(CmA, BmA) / dot(BmA, BmA)
        let D = A + BmA * t
        
        return NSColor(red: CGFloat(D.x), green: CGFloat(D.y), blue: CGFloat(D.z), alpha: 1.0).usingColorSpace(.sRGB)!
    }
    
    private func locationFor(color: NSColor) throws -> CGPoint {
        // Determine which transition contains the 'fromColor' that is closest in 'hue'
        // to the color.
        if self.transitions.isEmpty { loadTransitions() }
        guard let closestTransition = transitions.enumerated()
            .map({
                // Add distance between the two mired values
                let colorMired = mired(fromColor: color)
                let fromColorMired = mired(fromColor: $1.fromColor)

                return ($0, abs(colorMired - fromColorMired))
            })
            .sorted(by: { $0.1 < $1.1 })
            .first
        else { throw GradientError.colorNotInGradient(color: color) }
        
        // The passed-in color may not be one that exists in the color wheel. Find the
        // closest color in the color wheel to the passed-in color.
        let transition = transitions[closestTransition.0]
        let closestColor = closestColor(inTransition: transition, toColor: color)
        
        // Determine what percentage of the transition the color belongs to by reversing
        // the calculations done to linearly interpolate between the transition's colors.
        // Because the passed-in color has been "pulled in" to the interpolation line, the
        // percentages of each color should be very nearly-identical - any one can be used.
        let pRed = Double(closestColor.redComponent).convert(fromMin: transition.fromColor.redComponent,
                                                             max: transition.toColor.redComponent,
                                                             toMin: 0,
                                                             max: 1.0)
        let pGreen = Double(closestColor.greenComponent).convert(fromMin: transition.fromColor.greenComponent,
                                                                 max: transition.toColor.greenComponent,
                                                                 toMin: 0,
                                                                 max: 1.0)
        let pBlue = Double(closestColor.blueComponent).convert(fromMin: transition.fromColor.blueComponent,
                                                               max: transition.toColor.blueComponent,
                                                               toMin: 0,
                                                               max: 1.0)
        
        let percentage = pRed != 0 ? pRed :
                         pGreen != 0 ? pGreen :
                         pBlue != 0 ? pBlue : 0
        
        var convertedY = percentage.convert(fromMin: 0.0, max: 1.0, toMin: transition.fromLocation, max: transition.toLocation)
        convertedY = convertedY.convert(fromMin: 0.0, max: 1.0, toMin: 0, max: size)
        
        return CGPoint(x: size / 2, y: convertedY)
    }
    
    private func colorAt(_ location: CGPoint) throws -> Color {
        // The color temperature picker is a linear gradient that runs from .top to
        // .bottom. Only the 'y' coordinate of 'location' is needed.
        // Make sure the coordinates are contrained to the wheel, otherwise the
        // color of the dropper will continue changing to one that isn't represented
        // within the wheel.
        let constrainted = constrainToBounds(location)
        let colorAtY = try color(forY: constrainted.y)
        return Color(nsColor: colorAtY)
    }
}

// MARK: - Preview

#Preview {
    // !!!: Colors must be using sRGB color space
    @Previewable @State var droppers: [PickerDropper] = [
        PickerDropper(color: Color(color(fromMired: 153)!))
    ]
    
    // Color Temperatures in the range of Hue Gamut C bulbs
    // !!!: Colors must be using sRGB color space
    let colors = [
        color(fromMired: 500)!,
        color(fromMired: 400)!,
        color(fromMired: 300)!,
        color(fromMired: 200)!,
        color(fromMired: 175)!,
        color(fromMired: 150)!,
        color(fromMired: 110)!
    ]
    
    ColorTemperaturePickerView(gradient: colors, droppers: $droppers)
        .frame(width: 150, height: 150)
        .padding(.top, 15)
        .padding()
}
