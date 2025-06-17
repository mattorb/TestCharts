import SwiftUI
import Charts
import Foundation

struct DataPoint: Identifiable {
  let id = UUID()
  let x: Double
  let y: Double
  let series: String
}

struct ChartConfig {
  static let minDomain: Double = 10
  static let maxDomain: Double = 100
  static let defaultDomain: Double = 100
  static let yRange: ClosedRange<Double> = -12...12
  static let xRange: ClosedRange<Double> = 0...100
}

struct ChartInteractionState {
  var scrollPosition: Double
  var visibleDomain: Double
  var selectedPoint: DataPoint?
  var lastZoomLocation: CGFloat?
  
  init(initialPosition: Double = ChartConfig.maxDomain / 2,
       initialDomain: Double = ChartConfig.maxDomain) {
    self.scrollPosition = initialPosition
    self.visibleDomain = initialDomain
    self.selectedPoint = nil
  }
  
  mutating func updateZoom(scale: Double, location: CGPoint, size: CGSize) {
    // Convert point to relative position (0-1)
    let relativeX = location.x / size.width
    
    // Calculate the current domain window
    let domainStart = scrollPosition - visibleDomain / 2
    
    // Find the data point at the zoom location
    let zoomPointInData = domainStart + visibleDomain * relativeX
    
    // Calculate new domain size
    let newDomain = visibleDomain / scale
    let clampedDomain = min(max(ChartConfig.minDomain, newDomain), ChartConfig.maxDomain)
    
    // Calculate new scroll position to maintain zoom point
    let newDomainStart = zoomPointInData - (clampedDomain * relativeX)
    let newScrollPosition = newDomainStart + clampedDomain / 2
    
    // Update state with clamped values
    visibleDomain = clampedDomain
    scrollPosition = min(max(clampedDomain / 2, newScrollPosition), ChartConfig.maxDomain - clampedDomain / 2)
  }
  
  mutating func updateScroll(dragRatio: Double) {
    let dataMove = dragRatio * visibleDomain
    let newPosition = scrollPosition - dataMove
    let minPosition = visibleDomain / 2
    let maxPosition = ChartConfig.maxDomain - visibleDomain / 2
    scrollPosition = min(max(minPosition, newPosition), maxPosition)
  }
  
  mutating func reset() {
    scrollPosition = ChartConfig.maxDomain / 2
    visibleDomain = ChartConfig.maxDomain
    selectedPoint = nil
  }
}

struct ChartLegendItem: View {
  let series: String
  let isSelected: Bool
  let action: () -> Void
  
  private var color: Color {
    series == "Sine Wave" ? .blue : .purple
  }
  
  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
        Text(series)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .opacity(isSelected ? 1 : 0.5)
  }
}

struct ChartView: View {
  let data: [DataPoint]
  let title: String
  @Binding var selectedSeries: String?
  
  @State private var interaction = ChartInteractionState()
  @State private var scrollX: Double = ChartConfig.maxDomain / 2
  
  private func distance(_ p1: (x: Double, y: Double), _ p2: (x: Double, y: Double)) -> Double {
    let dx = p1.x - p2.x
    let dy = p1.y - p2.y
    return sqrt(dx * dx + dy * dy)
  }
  
  private func handleTap(at location: CGPoint, proxy: ChartProxy) {
    guard let xValue = proxy.value(atX: location.x, as: Double.self),
          let yValue = proxy.value(atY: location.y, as: Double.self) else { return }
    
    // Filter by series if one is selected
    let filteredData = selectedSeries == nil ? data : data.filter { $0.series == selectedSeries }
    
    // Find the nearest point by calculating actual distance to each point
    let tapPoint = (x: xValue, y: yValue)
    interaction.selectedPoint = filteredData.min(by: { point1, point2 in
      distance((x: point1.x, y: point1.y), tapPoint) < 
        distance((x: point2.x, y: point2.y), tapPoint)
    })
  }
  
  private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
    let dragRatio = value.translation.width / size.width
    withAnimation(.interactiveSpring(response: 0.3)) {
      interaction.updateScroll(dragRatio: dragRatio)
      scrollX = interaction.scrollPosition
    }
  }
  
  private var chartTitle: some View {
    HStack {
      Text(title)
        .font(.headline)
      
      Spacer()
      
      if interaction.visibleDomain < ChartConfig.maxDomain {
        Text(String(format: "%.1fx zoom", ChartConfig.maxDomain / interaction.visibleDomain))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      
      Button("Reset") {
        withAnimation(.spring()) {
          interaction.reset()
          scrollX = interaction.scrollPosition
        }
      }
      .font(.caption)
      .foregroundStyle(.blue)
    }
  }
  
  private var chartContent: some View {
    Chart {
      ForEach(data) { point in
        LineMark(
          x: .value("Index", point.x),
          y: .value("Value", point.y)
        )
        .foregroundStyle(by: .value("Series", point.series))
        .opacity(selectedSeries == nil || selectedSeries == point.series ? 1 : 0.2)
      }
      
      if let selectedPoint = interaction.selectedPoint {
        RuleMark(
          x: .value("Selected", selectedPoint.x)
        )
        .foregroundStyle(.gray.opacity(0.3))
        
        PointMark(
          x: .value("Index", selectedPoint.x),
          y: .value("Value", selectedPoint.y)
        )
        .foregroundStyle(selectedPoint.series == "Sine Wave" ? .blue : .purple)
        .symbolSize(100)
      }
    }
    .chartForegroundStyleScale([
      "Sine Wave": Color.blue,
      "Cosine Wave": Color.purple
    ])
    .chartYScale(domain: ChartConfig.yRange)
    .chartXScale(domain: ChartConfig.xRange)
    .chartXVisibleDomain(length: interaction.visibleDomain)
    .chartScrollPosition(x: $scrollX)
    .chartScrollableAxes(.horizontal)
    .chartLegend(position: .bottom)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 5))
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 5))
    }
  }
  
  private var selectedPointInfo: some View {
    Group {
      if let selectedPoint = interaction.selectedPoint {
        HStack {
          Text(String(format: "X: %.0f", selectedPoint.x))
          Text(String(format: "Y: %.2f", selectedPoint.y))
          Text(selectedPoint.series)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }
  
  private var legendView: some View {
    HStack(spacing: 16) {
      ForEach(["Sine Wave", "Cosine Wave"], id: \.self) { series in
        ChartLegendItem(
          series: series,
          isSelected: selectedSeries == nil || selectedSeries == series
        ) {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedSeries = selectedSeries == series ? nil : series
          }
        }
      }
    }
    .padding(.top, 4)
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      chartTitle
      
      chartContent
        .chartOverlay { proxy in
          GeometryReader { geometry in
            Color.clear
              .contentShape(Rectangle())
              .gesture(
                MagnificationGesture()
                  .onChanged { scale in
                    withAnimation(.interactiveSpring(response: 0.3)) {
                      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                      interaction.updateZoom(scale: scale, location: center, size: geometry.size)
                      scrollX = interaction.scrollPosition
                    }
                  }
              )
              .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { value in
                    if value.translation == .zero {
                      handleTap(at: value.location, proxy: proxy)
                    } else {
                      handleDrag(value, size: geometry.size)
                    }
                  }
                  .onEnded { _ in
                    interaction.selectedPoint = nil
                  }
              )
          }
        }
      
      selectedPointInfo
      legendView
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(uiColor: .systemBackground))
        .shadow(radius: 2)
    )
  }
}

struct ContentView: View {
  static let sampleData: [DataPoint] = {
    let sineData = (0..<100).map { i in
      let x = Double(i)
      return DataPoint(x: x, y: sin(x * 0.1) * 10, series: "Sine Wave")
    }
    
    let cosineData = (0..<100).map { i in
      let x = Double(i)
      return DataPoint(x: x, y: cos(x * 0.1) * 10, series: "Cosine Wave")
    }
    
    return sineData + cosineData
  }()
  
  @State private var selectedSeries: String?
  
  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        Text("Interactive Wave Charts")
          .font(.title)
          .padding(.top)
        
        Text("Pinch to zoom • Drag to pan • Tap to select")
          .font(.caption)
          .foregroundStyle(.secondary)
        
        ChartView(
          data: ContentView.sampleData,
          title: "Large Chart",
          selectedSeries: $selectedSeries
        )
        
        ChartView(
          data: ContentView.sampleData,
          title: "Medium Chart",
          selectedSeries: $selectedSeries
        )
        .frame(width: UIScreen.main.bounds.width * 0.75)
        
        ChartView(
          data: ContentView.sampleData,
          title: "Small Chart",
          selectedSeries: $selectedSeries
        )
        .frame(width: UIScreen.main.bounds.width * 0.5)
      }
      .padding()
    }
  }
}

#Preview("Light Mode") {
  ContentView()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
  ContentView()
    .preferredColorScheme(.dark)
}
