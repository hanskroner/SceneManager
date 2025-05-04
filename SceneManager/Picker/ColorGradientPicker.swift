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
    
    @State private var zIndexDroppers: [PickerDropper] = []
    
    private func zIndexSort(top: PickerDropper) {
        if let index = zIndexDroppers.firstIndex(of: top) {
            zIndexDroppers.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        } else {
            zIndexDroppers.insert(top, at: 0)
        }
        
        for (index, dropper) in zIndexDroppers.reversed().enumerated() {
            dropper.zIndex = Double(index)
        }
    }

    private struct Transition: Equatable {
        let fromLocation: Double
        let toLocation: Double
        let fromColor: NSColor
        let toColor: NSColor
        
        func contains(color: NSColor) -> Bool {
            let max = max(fromColor.hueComponent, toColor.hueComponent)
            let min = min(fromColor.hueComponent, toColor.hueComponent)
            let inRange = min <= color.hueComponent && max >= color.hueComponent
            
            // Use the hue distance between ranges to determine if we should be looking
            // for colors within the range of the transition (clockwise transition) or
            // outside the range (counter-clockwise transition).
            return (max - min) <= 0.5 ? inRange : !inRange
        }

        func color(forPercent percent: Double) -> NSColor {
            // Linear interpolation in HSB
            // Determine clockwise and counter-clockwise distance between hues
            let fromHue = fromColor.hueComponent
            let toHue = toColor.hueComponent
            let distCCW = (fromHue >= toHue) ? fromHue - toHue : 1 + fromHue - toHue
            let distCW = (fromHue >= toHue) ? 1 + toHue - fromHue : toHue - fromHue
            
            var hue = (distCW <= distCCW) ? fromHue + (distCW * percent) : fromHue - (distCCW * percent)
            if hue < 0 { hue = 1 + hue }
            if hue > 1 { hue = hue - 1 }
            
            let satuartion = fromColor.saturationComponent + percent * (toColor.saturationComponent - fromColor.saturationComponent)
            let brightness = fromColor.brightnessComponent + percent * (toColor.brightnessComponent - fromColor.brightnessComponent)
            let alpha = fromColor.alphaComponent + percent * (toColor.alphaComponent - fromColor.alphaComponent)
            
            return NSColor(hue: hue, saturation: satuartion, brightness: brightness, alpha: alpha).usingColorSpace(.sRGB)!
        }
        
        func percent(forColor color: NSColor) -> Double {
            let max = max(fromColor.hueComponent, toColor.hueComponent)
            let min = min(fromColor.hueComponent, toColor.hueComponent)
            
            if (max - min) <= 0.5 {
                // clockwise
                return (fromColor.hueComponent - color.hueComponent) / (fromColor.hueComponent - toColor.hueComponent)
            } else {
                // counter-clockwise
                return (color.hueComponent - fromColor.hueComponent) / (1 - fromColor.hueComponent + toColor.hueComponent)
            }
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
                        // Add to zIndex Array
                        zIndexSort(top: dropper)
                        
                        do {
                            dropper.location = try location(forColor: NSColor(dropper.color))
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
        .onChange(of: selection) { previousDropper, newDropper in
            // Sort zIndex array
            guard let newDropper else { return }
            zIndexSort(top: newDropper)
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
    
    private func color(forAngle angle: Double) throws -> NSColor {
        if self.transitions.isEmpty { loadTransitions() }

        // Convert the angle to a percentage of the overall gradient. Then convert that
        // to a percentage relative to the transition where the color is located and
        // obtain the color at that location.
        let percent = angle.convert(fromZeroToMax: 2 * .pi, toZeroToMax: 1.0)
        
        // FIXME: Throw instead of fatalError
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
    
    private func location(forColor color: NSColor) throws -> CGPoint {
        if self.transitions.isEmpty { loadTransitions() }
        let transitionsInRange: [(index: Int, transition: Transition, location: CGPoint, color: NSColor)] = try transitions.enumerated()
            // Multiple transitions can contain the hue of the passed-in color. This happens
            // because the last transition in the gradient goes 'from' the last color in the
            // array beck 'to' the first color.
            .filter({ (index, transition) in
                transition.contains(color: color)
            })
            // To decide which of the (potentially) two possible transitions is a better
            // candidate to contain the passed-in color, it is necessary to obtain the
            // color that would result if each transition was chosen - and pick the transition
            // that has the closest color.
            .map({ (index, transition) in
                // Find out where in the transition the passed-in color's hue is.
                let radius = size / 2
                let percent = transition.percent(forColor: color)
                
                // Convert the percentage to an angle.
                let percentWheel = percent.convert(fromMin: 0.0, max: 1.0, toMin: transition.fromLocation, max: transition.toLocation)
                var convertedRadians = percentWheel.convert(fromZeroToMax: 1.0, toZeroToMax: 2 * .pi)
                
                // The colors gradient has been set to start at 270º instead of 0º, so this needs
                // to move forward (clockwise) 90º (𝜋/2) by subtracting 𝜋/2 - modulo 2𝜋.
                convertedRadians = (convertedRadians - (.pi / 2)).truncatingRemainder(dividingBy: 2 * .pi)
                convertedRadians = convertedRadians > 0 ? convertedRadians : (2 * .pi + convertedRadians)
                
                let normalizedPercent = percentWheel.convert(fromMin: transition.fromLocation, max: transition.toLocation, toMin: 0.0, max: 1.0)
                let maxSaturation = transition.color(forPercent: normalizedPercent).saturationComponent
                let convertedSaturation = Double(color.saturationComponent).convert(fromZeroToMax: maxSaturation, toZeroToMax: radius)
                
                // Convert to cartesian
                let origin = CGPoint(x: radius, y: radius)
                let location = CGPoint(x: (convertedSaturation * cos(convertedRadians)) + origin.x,
                                       y: (convertedSaturation * sin(convertedRadians)) + origin.y)
                
                return (index, transition, location, NSColor(try colorAt(location)))
            })
            // Sort the possible options by how close they match the passed-in color.
            // !!!: Colors may exist multiple places in the wheel
            //      Some identical colors might exist at multiple locations. This is most
            //      obvious with wheels that have the same start and end colors, and only
            //      a single color between them. In these cases, the location of the
            //      passed-in color may not be consistently the same.
            .sorted(by: { (arg0, arg1) in
                let (_, _, _, lhsTargetColor) = arg0
                let (_, _, _, rhsTargetColor) = arg1
                let lhs = lhsTargetColor
                let rhs = rhsTargetColor
                
                return (abs(lhs.hueComponent - color.hueComponent),abs(lhs.saturationComponent - color.saturationComponent), abs(lhs.brightnessComponent - color.brightnessComponent)) < (abs(rhs.hueComponent - color.hueComponent), abs(rhs.saturationComponent - color.saturationComponent), abs(rhs.brightnessComponent - color.brightnessComponent))
            })
        
        guard let desiredSelection = transitionsInRange.first else { throw GradientError.colorNotInGradient(color: color)}
        
        return desiredSelection.location
    }
    
    private func colorAt(_ location: CGPoint) throws -> Color {
        let origin = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2
        
        // Convert the incoming location to polar coordinates.
        let constrainted = constrainToBounds(location)
        let hue = atan2(constrainted.y - origin.y, constrainted.x - origin.x)
        let hueRadians = hue > 0 ? hue : (2 * .pi + hue)
        let saturation = sqrt(pow(constrainted.x - origin.x, 2) + pow(constrainted.y - origin.y, 2))
        
        // The colors gradient has been set to start at 270º instead of 0º, so this needs
        // to move back (counter-clockwise) 90º (𝜋/2) by adding 𝜋/2 - modulo 2𝜋.
        // 'saturation' is a value between 0.0 and 1.0 that indicates how far along the
        // radius the tap happened. When getting a color, it should be the percentage of
        // the saturation of the color in the gradient.
        if self.transitions.isEmpty { loadTransitions() }
        let angle = Double((hueRadians + (.pi / 2)).truncatingRemainder(dividingBy: 2 * .pi))
        let colorAtAngle = try color(forAngle: angle)
        
        // The saturation value of the color found in the gradient needs to be converted
        // to be in the range of '0' to 'maxSaturation'.
        let maxSaturation = colorAtAngle.saturationComponent
        let saturationValue = Double(saturation).convert(fromZeroToMax: radius, toZeroToMax: maxSaturation)
        
        let colorAt = NSColor(hue: colorAtAngle.hueComponent,
                              saturation: saturationValue,
                              brightness: colorAtAngle.brightnessComponent,
                              alpha: 1.0).usingColorSpace(.sRGB)!
        
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
