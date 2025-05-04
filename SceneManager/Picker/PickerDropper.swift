//
//  PickerDropper.swift
//  SceneManager
//
//  Created by Hans Kröner on 26/04/2025.
//

import SwiftUI

// MARK: - Picker Dropper

@Observable
class PickerDropper: Identifiable, Hashable {
    static func == (lhs: PickerDropper, rhs: PickerDropper) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id: UUID
    
    var color: Color
    var location: CGPoint
    
    var image: String?
    
    var isDragging: Bool = false
    var isSelected: Bool = false
    
    var zIndex: Double = 0
    
    init(id: UUID = UUID(), color: Color = .white, location: CGPoint = CGPoint(x: 0, y: 0), image: String? = nil) {
        self.id = id
        
        self.color = color
        self.location = location
        
        self.image = image
    }
}

struct PickerDropperView: View {
    @Binding var dropper: PickerDropper
    
    var onLocationChanged = {}
    
    var body: some View {
        ZStack {
            Dropper()
                .strokeBorder(isDark(dropper.color) ? .white : .black, lineWidth: dropper.isSelected ? 3 : 0)
                .fill(dropper.color)
                .aspectRatio(contentMode: .fit)
                .rotationEffect(Angle(degrees: 180), anchor: .center)
                .onChange(of: dropper.location) { oldValue, newValue in
                    self.onLocationChanged()
                }
                .shadow(color: Color("shadow"), radius: 3, y: 1)
                .id(dropper.id)
            
            if let image = dropper.image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isDark(dropper.color) ? .white : .black)
                    .padding(6)
                    .padding(.bottom, 6)
            }
        }
        .zIndex(dropper.isSelected ? 10 : dropper.zIndex)
    }
    
    func onLocationChanged(_ callback: @escaping () -> ()) -> some View {
        PickerDropperView(dropper: $dropper, onLocationChanged: callback)
    }
}

// MARK: - Dropper Shape

struct Dropper: InsettableShape {
    var insetAmount = 0.0
    
    func inset(by amount: CGFloat) -> some InsettableShape {
        var dropper = self
        dropper.insetAmount += amount
        
        return dropper
}
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        
        path.move(to: CGPoint(x: 0.49008 * width, y: 0.00407 * height))
        path.addCurve(to: CGPoint(x: 0.11171 * width, y: 0.61173 * height),
                      control1: CGPoint(x: 0.47466 * width, y: 0.02022 * height),
                      control2: CGPoint(x: 0.11171 * width, y: 0.40174 * height))
        path.addCurve(to: CGPoint(x: 0.5 * width, y: height),
                      control1: CGPoint(x: 0.11171 * width, y: 0.82586 * height),
                      control2: CGPoint(x: 0.28589 * width, y: height))
        path.addCurve(to: CGPoint(x: 0.88829 * width, y: 0.61173 * height),
                      control1: CGPoint(x: 0.71419 * width, y: height),
                      control2: CGPoint(x: 0.88829 * width, y: 0.82584 * height))
        path.addCurve(to: CGPoint(x: 0.50992 * width, y: 0.00407 * height),
                      control1: CGPoint(x: 0.88829 * width, y: 0.40174 * height),
                      control2: CGPoint(x: 0.52535 * width, y: 0.02021 * height))
        path.addCurve(to: CGPoint(x: 0.49008 * width, y: 0.00407 * height),
                      control1: CGPoint(x: 0.50471 * width, y: -0.00136 * height),
                      control2: CGPoint(x: 0.49524 * width, y: -0.00136 * height))
        path.closeSubpath()
        
        return path
    }
}
