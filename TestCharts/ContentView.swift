import SwiftUI
import Charts

struct DataPoint: Identifiable {
  let id = UUID()
  let x: Double
  let y: Double
  let series: String
}

struct ChartConfig {
  static let minDomain: Double = 10
  static let maxDomain: Double = 100
  static let defaultDomain: Double = 100 // Changed to maximum for initial state
  static let yRange: ClosedRange<Double> = -12...12
  static let xRange: ClosedRange<Double> = 0...100
}

struct ChartInteractionState {
  var scrollPosition: Double
  var visibleDomain: Double
  var selectedPoint: DataPoint?
  
  init(initialPosition: Double = ChartConfig.maxDomain / 2, // Center the view
       initialDomain: Double = ChartConfig.maxDomain) { // Start fully zoomed out
    self.scrollPosition = initialPosition
    self.visibleDomain = initialDomain
    self.selectedPoint = nil
  }
  
  mutating func updateZoom(scale: Double) {
    let newDomain = visibleDomain / scale
    visibleDomain = min(max(ChartConfig.minDomain, newDomain), ChartConfig.maxDomain)
  }
  
  mutating func updateScroll(dragRatio: Double) {
    let dataMove = dragRatio * visibleDomain
    scrollPosition = min(max(0, scrollPosition - dataMove), ChartConfig.maxDomain)
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
  @State private var scrollX: Double = ChartConfig.maxDomain / 2 // Start at center
  
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
  
  private func handleTap(at point: CGPoint, proxy: ChartProxy) {
    guard let xValue = proxy.value(atX: point.x, as: Double.self) else { return }
    let filteredData = selectedSeries == nil ? data : data.filter { $0.series == selectedSeries }
    interaction.selectedPoint = filteredData.min(by: { abs($0.x - xValue) < abs($1.x - xValue) })
  }
  
  private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
    let dragRatio = value.translation.width / size.width
    withAnimation(.interactiveSpring(response: 0.3)) {
      interaction.updateScroll(dragRatio: dragRatio)
      scrollX = interaction.scrollPosition
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
                      interaction.updateZoom(scale: scale)
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
