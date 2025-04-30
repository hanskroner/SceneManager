//
//  BrightnessSlider.swift
//  SceneManager
//
//  Created by Hans Kröner on 28/04/2025.
//

import SwiftUI

fileprivate struct Constant {
    static let cornerRadius: CGFloat = 20
    
    static let thumbHeight: CGFloat = 20
    
    static var halfThumbHeight: CGFloat {
        thumbHeight / 2
    }
}

public struct BrightnessSlider: View {
    @Binding private var value: Double

    private let image: String
    private let sliderColor: Color
    private let range: ClosedRange<Double>
    
    @State private var size: CGSize = .zero
    @State private var offset: CGFloat = 0

    public init(image: String, sliderColor: Color = .white, value: Binding<Double>) {
        self.image = image
        self.sliderColor = sliderColor
        self._value = value
        self.range = 0...100
    }

    public var body: some View {
        VStack(alignment: .leading) {
            GeometryReader { proxy in
                SliderView(
                    offset: $offset,
                    size: proxy.size,
                    sliderColor: sliderColor,
                    image: image,
                    onChange: updateValue
                )
                .onAppear {
                    size = proxy.size
                    updateOffset(to: value)
                }
                .onChange(of: value) { previousValue, newValue in
                    updateOffset(to: newValue)
                }
            }
        }
        .padding(.horizontal, 3)
    }

    private func updateValue() {
        let percentage = Double(offset / (size.height - Constant.thumbHeight))
        value = range.lowerBound + percentage * (range.upperBound - range.lowerBound)
    }

    private func updateOffset(to value: Double) {
        let percentage = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let newOffset = percentage * (size.height - Constant.thumbHeight)
        offset = max(0, min(newOffset, size.height - Constant.thumbHeight))
    }
}

private struct SliderView: View {
    @Binding var offset: CGFloat
    
    let size: CGSize
    let sliderColor: Color
    let image: String
    let onChange: () -> Void
    
    @GestureState private var dragOffsetY: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isTapping: Bool = false

    private var sliderFillHeight: CGFloat {
        let fillAmount = min(offset + Constant.halfThumbHeight, size.height - Constant.halfThumbHeight)
        return max(Constant.halfThumbHeight, fillAmount) + Constant.halfThumbHeight
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isTapping = true
                updateOffset(at: size.height - value.location.y)
                onChange()
            }
            .onEnded { _ in
                isTapping = false
            }
            .simultaneously(with: DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isTapping = false
                    isDragging = true
                    updateOffset(at: size.height - value.location.y)
                    onChange()
                }
                .onEnded { _ in
                    isDragging = false
                }
            )
    }
    
    private func updateOffset(at location: CGFloat) {
        let adjustedLocation = location - Constant.halfThumbHeight
        offset = max(0, min(adjustedLocation, size.height - Constant.thumbHeight))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            sliderTrack
            sliderFill
                .overlay(alignment: .bottom) {
                    sliderThumb
                }
        }
        .gesture(dragGesture)
        .animation(isTapping && !isDragging ? .smooth(duration: 0.25, extraBounce: 0.0) : nil, value: offset)
    }

    private var sliderTrack: some View {
        RoundedRectangle(cornerRadius: Constant.cornerRadius)
            .fill(Color("track"))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Constant.cornerRadius))
    }

    private var sliderFill: some View {
        RoundedRectangle(cornerRadius: Constant.cornerRadius)
            .fill(sliderColor)
            .frame(width: size.width, height: sliderFillHeight)
    }

    private var sliderThumb: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isDark(sliderColor) ? .white : Color(NSColor.windowBackgroundColor), lineWidth: isDragging || isTapping ? 1.5 : 0)
            .frame(width: size.width + 6, height: Constant.thumbHeight)
            .foregroundStyle(.clear)
            .overlay {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isDark(sliderColor) ? .white : .black)
            }
            .background {
                LinearGradient(gradient: Gradient(colors: [
                    sliderColor.adjust(brightness: -0.2),
                    sliderColor,
                    sliderColor.adjust(brightness: 0.2)
                ]), startPoint: .bottom, endPoint: .top)
                .brightness(isDragging || isTapping ? -0.15 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Color("shadow"), radius: 3, y: 1)
            .offset(y: -offset)
    }
}

#Preview {
    @Previewable @State var value: Double = 50.0
    
    VStack {
        BrightnessSlider(image: "E00-D-57357", sliderColor: .red, value: $value)
            .frame(width: 75, height: 300)
            .padding(.horizontal, 30)
            .padding(.top, 20)
        
        Text("Value: \(String(format: "%.0f", value))")
            .padding(.vertical, 6)
    }
}
