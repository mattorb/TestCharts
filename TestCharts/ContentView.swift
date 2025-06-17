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
    let minScrollPosition = 0.0
    let maxScrollPosition = ChartConfig.maxDomain - clampedDomain / 2
    
    // Update state with clamped values
    visibleDomain = clampedDomain
    scrollPosition = min(max(minScrollPosition, newDomainStart + clampedDomain / 2), maxScrollPosition)
  }
  
  mutating func updateScroll(dragRatio: Double) {
    let dataMove = dragRatio * visibleDomain
    let newPosition = scrollPosition - dataMove
    let minPosition = 0.0
    let maxPosition = ChartConfig.maxDomain - visibleDomain / 2
    scrollPosition = min(max(minPosition, newPosition), maxPosition)
  }
  
  mutating func reset() {
    scrollPosition = ChartConfig.maxDomain / 2
    visibleDomain = ChartConfig.maxDomain
    selectedPoint = nil
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
    
    // Calculate the visible domain window
    let domainStart = interaction.scrollPosition - interaction.visibleDomain / 2
    let domainEnd = interaction.scrollPosition + interaction.visibleDomain / 2
    
    // Filter points to visible domain plus a small buffer
    let buffer = interaction.visibleDomain * 0.1 // 10% buffer
    let visibleData = filteredData.filter { point in
      point.x >= (domainStart - buffer) && point.x <= (domainEnd + buffer)
    }
    
    // Find the nearest point considering the chart's scale
    let tapPoint = (x: xValue, y: yValue)
    interaction.selectedPoint = visibleData.min(by: { point1, point2 in
      let dist1 = getScaledDistance(from: tapPoint, to: point1, proxy: proxy)
      let dist2 = getScaledDistance(from: tapPoint, to: point2, proxy: proxy)
      return dist1 < dist2
    })
  }
  
  private func getScaledDistance(from tap: (x: Double, y: Double), to point: DataPoint, proxy: ChartProxy) -> Double {
    // Convert data points to screen coordinates
    guard let tapX = proxy.position(forX: tap.x),
          let tapY = proxy.position(forY: tap.y),
          let pointX = proxy.position(forX: point.x),
          let pointY = proxy.position(forY: point.y) else {
      return .infinity
    }
    
    // Calculate distance in screen coordinates
    let dx = tapX - pointX
    let dy = tapY - pointY
    return sqrt(dx * dx + dy * dy)
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
        .frame(width:400)
        
        ChartView(
          data: ContentView.sampleData,
          title: "Medium Chart",
          selectedSeries: $selectedSeries
        )
        .frame(width:300)
        
        ChartView(
          data: ContentView.sampleData,
          title: "Small Chart",
          selectedSeries: $selectedSeries
        )
        .frame(width:200)
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
