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
  
  private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
    // Convert tap location to data coordinates using our robust transformation
    guard let tapDataPoint = screenToDataCoordinates(
      screenPoint: location, 
      geometry: geometry, 
      proxy: proxy
    ) else { return }
    
    // Filter by series if one is selected
    let filteredData = selectedSeries == nil ? data : data.filter { $0.series == selectedSeries }
    
    // Calculate the visible domain window
    let domainStart = interaction.scrollPosition - interaction.visibleDomain / 2
    let domainEnd = interaction.scrollPosition + interaction.visibleDomain / 2
    
    // Filter points to visible domain plus a small buffer
    let buffer = interaction.visibleDomain * 0.1
    let visibleData = filteredData.filter { point in
      point.x >= (domainStart - buffer) && point.x <= (domainEnd + buffer)
    }
    
    // Find the nearest point using robust distance calculation
    interaction.selectedPoint = visibleData.min(by: { point1, point2 in
      let dist1 = calculateTapDistance(tapPoint: tapDataPoint, dataPoint: point1, geometry: geometry, proxy: proxy)
      let dist2 = calculateTapDistance(tapPoint: tapDataPoint, dataPoint: point2, geometry: geometry, proxy: proxy)
      return dist1 < dist2
    })
  }
  
  private func screenToDataCoordinates(screenPoint: CGPoint, geometry: GeometryProxy, proxy: ChartProxy) -> (x: Double, y: Double)? {
    // Method 1: Try using ChartProxy directly (works in most cases)
    if let xValue = proxy.value(atX: screenPoint.x, as: Double.self),
       let yValue = proxy.value(atY: screenPoint.y, as: Double.self) {
      return (x: xValue, y: yValue)
    }
    
    // Method 2: Manual transformation (fallback for edge cases)
    let relativeX = screenPoint.x / geometry.size.width
    let relativeY = 1.0 - (screenPoint.y / geometry.size.height) // Flip Y
    
    // Calculate visible domain bounds
    let domainStart = interaction.scrollPosition - interaction.visibleDomain / 2
    let domainEnd = interaction.scrollPosition + interaction.visibleDomain / 2
    
    // Map to data coordinates
    let xValue = domainStart + (domainEnd - domainStart) * relativeX
    let yRange = ChartConfig.yRange
    let yValue = yRange.lowerBound + (yRange.upperBound - yRange.lowerBound) * relativeY
    
    return (x: xValue, y: yValue)
  }
  
  private func dataToScreenCoordinates(dataPoint: (x: Double, y: Double), geometry: GeometryProxy, proxy: ChartProxy) -> CGPoint? {
    // Try using ChartProxy
    if let screenX = proxy.position(forX: dataPoint.x),
       let screenY = proxy.position(forY: dataPoint.y) {
      return CGPoint(x: screenX, y: screenY)
    }
    
    // Manual fallback
    let domainStart = interaction.scrollPosition - interaction.visibleDomain / 2
    let domainEnd = interaction.scrollPosition + interaction.visibleDomain / 2
    
    guard domainEnd > domainStart else { return nil }
    
    let relativeX = (dataPoint.x - domainStart) / (domainEnd - domainStart)
    let yRange = ChartConfig.yRange
    let relativeY = (dataPoint.y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
    
    let screenX = relativeX * geometry.size.width
    let screenY = (1.0 - relativeY) * geometry.size.height // Flip Y
    
    return CGPoint(x: screenX, y: screenY)
  }
  
  private func calculateTapDistance(tapPoint: (x: Double, y: Double), dataPoint: DataPoint, geometry: GeometryProxy, proxy: ChartProxy) -> Double {
    // Convert both points to screen coordinates for accurate distance
    guard let tapScreen = dataToScreenCoordinates(dataPoint: tapPoint, geometry: geometry, proxy: proxy),
          let pointScreen = dataToScreenCoordinates(dataPoint: (x: dataPoint.x, y: dataPoint.y), geometry: geometry, proxy: proxy) else {
      // Fallback to weighted data coordinate distance
      let xWeight = geometry.size.width / interaction.visibleDomain
      let yWeight = geometry.size.height / (ChartConfig.yRange.upperBound - ChartConfig.yRange.lowerBound)
      
      let dx = (tapPoint.x - dataPoint.x) * xWeight
      let dy = (tapPoint.y - dataPoint.y) * yWeight
      return sqrt(dx * dx + dy * dy)
    }
    
    // Calculate screen space distance
    let dx = tapScreen.x - pointScreen.x
    let dy = tapScreen.y - pointScreen.y
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
                      handleTap(at: value.location, proxy: proxy, geometry: geometry)
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
