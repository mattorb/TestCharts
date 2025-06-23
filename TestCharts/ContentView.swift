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
  
  init(initialPosition: Double = ChartConfig.maxDomain / 2,
       initialDomain: Double = ChartConfig.maxDomain) {
    self.scrollPosition = initialPosition
    self.visibleDomain = initialDomain
    self.selectedPoint = nil
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
  @State private var debugTimer: Timer?
  
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
      proxy: proxy,
      actualScrollX: scrollX
    ) else { return }
    
    // Debug: Print tap details and actual domain bounds
    if let leftValue = proxy.value(atX: 0, as: Double.self),
       let rightValue = proxy.value(atX: geometry.size.width, as: Double.self) {
      print("ChartProxy actual domain: \(leftValue) to \(rightValue)")
    }
    print("Tap at screen: (\(location.x), \(location.y)) -> data: (\(tapDataPoint.x), \(tapDataPoint.y))")
//    print("Now using ChartProxy domain: \(domainStart) to \(domainEnd)")
    
    // Filter by series if one is selected
    let filteredData = selectedSeries == nil ? data : data.filter { $0.series == selectedSeries }
    
    // Get actual domain bounds from ChartProxy
    let domainStart: Double
    let domainEnd: Double
    
    if let leftValue = proxy.value(atX: 0, as: Double.self),
       let rightValue = proxy.value(atX: geometry.size.width, as: Double.self) {
      domainStart = leftValue
      domainEnd = rightValue
    } else {
      // Fallback if ChartProxy fails
      domainStart = 0
      domainEnd = ChartConfig.maxDomain
    }
    
    // Filter points to visible domain plus a small buffer
    let buffer = (domainEnd - domainStart) * 0.1
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
  
  private func screenToDataCoordinates(screenPoint: CGPoint, geometry: GeometryProxy, proxy: ChartProxy, actualScrollX: Double) -> (x: Double, y: Double)? {
    // Trust ChartProxy - it handles all zoom/scroll transformations correctly
    guard let xValue = proxy.value(atX: screenPoint.x, as: Double.self),
          let yValue = proxy.value(atY: screenPoint.y, as: Double.self) else {
      return nil
    }
    
    return (x: xValue, y: yValue)
  }
  
  private func dataToScreenCoordinates(dataPoint: (x: Double, y: Double), geometry: GeometryProxy, proxy: ChartProxy) -> CGPoint? {
    // Trust ChartProxy - it handles zoom/scroll automatically
    guard let screenX = proxy.position(forX: dataPoint.x),
          let screenY = proxy.position(forY: dataPoint.y) else {
      return nil
    }
    
    return CGPoint(x: screenX, y: screenY)
  }
  
  private func calculateTapDistance(tapPoint: (x: Double, y: Double), dataPoint: DataPoint, geometry: GeometryProxy, proxy: ChartProxy) -> Double {
    // Use screen coordinate distance - ChartProxy handles transformations correctly
    guard let tapScreen = dataToScreenCoordinates(dataPoint: tapPoint, geometry: geometry, proxy: proxy),
          let pointScreen = dataToScreenCoordinates(dataPoint: (x: dataPoint.x, y: dataPoint.y), geometry: geometry, proxy: proxy) else {
      // If screen conversion fails, fall back to simple data coordinate distance
      let dx = tapPoint.x - dataPoint.x
      let dy = tapPoint.y - dataPoint.y
      return sqrt(dx * dx + dy * dy)
    }
    
    let dx = tapScreen.x - pointScreen.x
    let dy = tapScreen.y - pointScreen.y
    return sqrt(dx * dx + dy * dy)
  }
  
  
  private var chartTitle: some View {
    HStack {
      Text(title)
        .font(.headline)
      
      Spacer()
      
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
    .onChange(of: scrollX) { _, newValue in
      interaction.scrollPosition = newValue
    }
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
  
  @ViewBuilder
  private var debugInfo: some View {
    #if DEBUG
    VStack(alignment: .leading, spacing: 2) {
      Text("Debug Info:")
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      
      HStack {
        Text(String(format: "Visible Domain: %.1f", interaction.visibleDomain))
        Text(String(format: "Scroll Position: %.1f", interaction.scrollPosition))
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      
      
      HStack {
        Text("Domain: Use ChartProxy for accurate bounds")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      
      HStack {
        Text(String(format: "Chart ScrollX: %.1f", scrollX))
        Text(String(format: "Internal ScrollPos: %.1f", interaction.scrollPosition))
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      
      // Add Chart's actual domain bounds using ChartProxy
      VStack(alignment: .leading, spacing: 1) {
        Text("Chart Framework Values:")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.orange)
        
        // We'll need to pass proxy info here - let's add it as a parameter
      }
      .font(.caption2)
      .foregroundStyle(.orange)
    }
    .padding(.top, 4)
    #endif
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      chartTitle
      
      chartContent
        .chartOverlay { proxy in
          GeometryReader { geometry in
            Color.clear
              .contentShape(Rectangle())
              .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { value in
                    if value.translation == .zero {
                      handleTap(at: value.location, proxy: proxy, geometry: geometry)
                    }
                    // Let Chart framework handle drag/pan - don't interfere
                  }
                  .onEnded { _ in
                    interaction.selectedPoint = nil
                  }
              )
          }
        }
      
      selectedPointInfo
      
      debugInfo
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
        
        Text("Drag to pan • Tap to select")
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
