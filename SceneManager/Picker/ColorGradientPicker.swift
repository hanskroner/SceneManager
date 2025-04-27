//
//  ColorGradientPicker.swift
//  SceneManager
//
//  Created by Hans Kröner on 12/04/2025.
//

import SwiftUI
import simd
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.picker", category: "gradient-picker")

// MARK: - Color Gradient Picker

struct ColorGradientPickerView: View {
    let gradient: [NSColor]
    
    @Binding var droppers: [PickerDropper]
    @Binding var selection: PickerDropper?
    
    private let bottomWhite: Color = .init(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.45)
    private let topWhite: Color = .init(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.95)
    
    @State private var size: CGFloat = 0.0
    @State private var transitions: [Transition] = []

    private struct Transition {
        let fromLocation: Double
        let toLocation: Double
        let fromColor: NSColor
        let toColor: NSColor

        func color(forPercent percent: Double) -> NSColor {
            let normalizedPercent = percent.convert(fromMin: fromLocation, max: toLocation, toMin: 0.0, max: 1.0)
            return NSColor.lerp(from: fromColor.rgba, to: toColor.rgba, percent: CGFloat(normalizedPercent))
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
            // Base gradient circle
            Circle()
                .fill(
                    AngularGradient(colors: gradient.map({ Color(nsColor: $0) }), center: .center, angle: .degrees(270))
                )
            
            // Blurred gradient circle to smooth color transitions
            Circle()
                .fill(
                    AngularGradient(colors: gradient.map({ Color(nsColor: $0) }), center: .center, angle: .degrees(270))
                )
                .blur(radius: 20)
                .clipShape(Circle())
                // TODO: Consider making a parameter
                .brightness(-0.08)
            
            // Dense white overlay to simulate lightness in the center
            Circle()
                .fill(
                    RadialGradient(gradient: Gradient(colors: [bottomWhite, .clear]), center: .center, startRadius: 0, endRadius: size * 0.46)
                )
            
            // Sparse white overlay to smooth out lightness
            Circle()
                .fill(
                    RadialGradient(gradient: Gradient(colors: [topWhite, .clear]), center: .center, startRadius: 10, endRadius: size * 0.5)
                )
                .blur(radius: 6.0)
            
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
                        dropper.color = colorAt(dropper.location)
                    }
                    .frame(height: size * 0.16)
                    .offset(x: 0, y: -size * 0.08)
                    .position(constrainToBounds(dropper.location))
                    .gesture(dragGesture)
                    .task {
                        dropper.location = locationFor(color: dropper.color)
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
    
    private func color(forAngle angle: Double) -> NSColor {
        if self.transitions.isEmpty { loadTransitions() }
        let percent = angle.convert(fromZeroToMax: 2 * .pi, toZeroToMax: 1.0)

        // FIXME: Throw instead of fatalError
        guard let transition = transition(forPercent: percent) else { fatalError("No transition") }

        return transition.color(forPercent: percent)
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
        let from = transition.fromColor.rgba
        let to = transition.toColor.rgba
        let outside = color.rgba
        
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
        let A = SIMD3(Float(from.red), Float(from.green), Float(from.blue))
        let B = SIMD3(Float(to.red), Float(to.green), Float(to.blue))
        let C = SIMD3(Float(outside.red), Float(outside.green), Float(outside.blue))
        
        // 'B' minus 'A' (BmA) and 'C' minus 'A' (CmA) are two vectors that represent the
        // direction from 'B' to 'A' and 'C' to 'A' respectively. They can be throught of
        // as two sides of a triangle, where the third side is made of of the projection
        // of 'C' onto 'AB' and is perpendicular to 'AB'.
        // 'D' is what we're looking for: the a point on 'AB' that is closests to 'C'.
        let BmA = B - A
        let CmA = C - A
        let t = dot(CmA, BmA) / dot(BmA, BmA)
        let D = A + BmA * t
        
        let closestColor = NSColor(red: CGFloat(D.x), green: CGFloat(D.y), blue: CGFloat(D.z), alpha: 1.0)
        
        return closestColor
    }
    
    private func locationFor(color: Color) -> CGPoint {
        let saturatedColor = NSColor(color)
        let redDistance = NSColor(hue: saturatedColor.hueComponent, saturation: saturatedColor.saturationComponent, brightness: 1.0, alpha: 1.0)
        
        // Determine which transition contains the 'fromColor' that is closest in 'hue'
        // to the color.
        if self.transitions.isEmpty { loadTransitions() }
        guard let closestTransition = transitions.enumerated()
            .map({ ($0, NSColor.hueDistance(lhs: redDistance, rhs: $1.fromColor)) })
            .sorted(by: { $0.1 < $1.1 })
            .first
        // FIXME: Throw instead of fatalError
        else { fatalError("Color not in any transition") }
        
        // The passed-in color may not be one that exists in the color wheel. Find the
        // closest color in the color wheel to the passed-in color.
        let from = transitions[closestTransition.0].fromColor.rgba
        let to = transitions[closestTransition.0].toColor.rgba
        let closestColor = closestColor(inTransition: transitions[closestTransition.0], toColor: redDistance)
        let distance = closestColor.rgba
        
        // Determine what percentage of the transition the color belongs to by reversing
        // the calculations done to linearly interpolate between the transition's colors.
        // Because the passed-in color has been "pulled in" to the interpolation line, the
        // percentages of each color should be very nearly-identical - any one can be used.
        let pRed = Double(distance.red).convert(fromMin: from.red, max: to.red, toMin: 0, max: 1.0)
        let pGreen = Double(distance.green).convert(fromMin: from.green, max: to.green, toMin: 0, max: 1.0)
        let pBlue = Double(distance.blue).convert(fromMin: from.blue, max: to.blue, toMin: 0, max: 1.0)
        
        let percentage = pRed != 0 ? pRed :
        pGreen != 0 ? pGreen :
        pBlue != 0 ? pBlue : 0
        
        // Convert the percentage to an angle.
        var convertedRadians = percentage.convert(fromMin: 0.0, max: 1.0, toMin: transitions[closestTransition.0].fromLocation, max: transitions[closestTransition.0].toLocation)
        convertedRadians = convertedRadians.convert(fromZeroToMax: 1.0, toZeroToMax: 2 * .pi)
        
        // The colors gradient has been set to start at 270º instead of 0º, so this needs
        // to move forward (clockwise) 90º (𝜋/2) by subtracting 𝜋/2 - modulo 2𝜋.
        convertedRadians = (convertedRadians - (.pi / 2)).truncatingRemainder(dividingBy: 2 * .pi)
        convertedRadians = convertedRadians > 0 ? convertedRadians : (2 * .pi + convertedRadians)
        
        // Correct saturation
        // 'saturation' is a value between 0.0 and 1.0 that indicates how far along the
        // radius the tap happened. When getting a color, it should be the percentage of
        // the saturation of the color in the gradient.
        let maxSaturationForColor = transitions[closestTransition.0].fromColor.saturationComponent
        let convertedSaturation = (saturatedColor.saturationComponent / maxSaturationForColor) * size / 2
        
        // Convert to cartesian
        let origin = CGPoint(x: size / 2, y: size / 2)
        let x = (convertedSaturation * cos(convertedRadians)) + origin.x
        let y = (convertedSaturation * sin(convertedRadians)) + origin.y
        
        return CGPoint(x: x, y: y)
    }
    
    private func colorAt(_ location: CGPoint) -> Color {
        let origin = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2
        
        let constrainted = constrainToBounds(location)
        let hue = atan2(constrainted.y - origin.y, constrainted.x - origin.x)
        let hueRadians = hue > 0 ? hue : (2 * .pi + hue)
        let saturation = sqrt(pow(constrainted.x - origin.x, 2) + pow(constrainted.y - origin.y, 2))
        
        // The colors gradient has been set to start at 270º instead of 0º, so this needs
        // to move back (counter-clockwise) 90º (𝜋/2) by adding 𝜋/2 - modulo 2𝜋.
        
        // 'saturation' is a value between 0.0 and 1.0 that indicates how far along the
        // radius the tap happened. When getting a color, it shoudl be the percentage of
        // the saturation of the color in the gradient.
        let coloratAngle = color(forAngle: (hueRadians + (.pi / 2)).truncatingRemainder(dividingBy: 2 * .pi))
        let colorAt = NSColor(hue: coloratAngle.hueComponent, saturation: coloratAngle.saturationComponent * (saturation / radius), brightness: 1.0, alpha: 1.0)
        
        return Color(nsColor: colorAt)
    }
}

// MARK: - Preview

#Preview {
    // Swift color names to sRGB Color
    // !!!: Colors must be using sRGB color space
    @Previewable @State var droppers: [PickerDropper] = [
        PickerDropper(color: Color(nsColor: NSColor(.yellow).usingColorSpace(.sRGB)!)),
        PickerDropper(color: Color(nsColor: NSColor(.cyan).usingColorSpace(.sRGB)!)),
        PickerDropper(color: Color(nsColor: NSColor(.purple).usingColorSpace(.sRGB)!))
    ]
    
    // Swift color names to sRGB Color
    // !!!: Colors must be using sRGB color space
    let colors = [
        NSColor(.red).usingColorSpace(.sRGB)!,
        NSColor(.yellow).usingColorSpace(.sRGB)!,
        NSColor(.green).usingColorSpace(.sRGB)!,
        NSColor(.cyan).usingColorSpace(.sRGB)!,
        NSColor(.blue).usingColorSpace(.sRGB)!,
        NSColor(.purple).usingColorSpace(.sRGB)!,
        NSColor(.red).usingColorSpace(.sRGB)!
    ]
    
    ColorGradientPickerView(gradient: colors, droppers: $droppers)
        .frame(width: 150, height: 150)
        .padding(.top, 15)
        .padding()
}
