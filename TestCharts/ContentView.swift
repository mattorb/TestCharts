import SwiftUI
import Charts

struct DataPoint: Identifiable {
  let id = UUID()
  let x: Double
  let y: Double
  let series: String
}

struct ContentView: View {
  // Generate sine wave data
  let sineData: [DataPoint] = (0..<100).map { i in
    let x = Double(i)
    return DataPoint(
      x: x,
      y: sin(x * 0.1) * 10,
      series: "Sine Wave"
    )
  }
  
  // Generate cosine wave data
  let cosineData: [DataPoint] = (0..<100).map { i in
    let x = Double(i)
    return DataPoint(
      x: x,
      y: cos(x * 0.1) * 10,
      series: "Cosine Wave"
    )
  }
  
  var allData: [DataPoint] {
    sineData + cosineData
  }
  
  @State private var selectedPoint: DataPoint?
  @State private var selectedSeries: String?
  
  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        Text("Wave Comparison")
          .font(.title)
          .padding(.top)
        
        // Large Chart - Full Width
        ChartView(
          data: allData,
          title: "Large Chart (100%)",
          selectedPoint: $selectedPoint,
          selectedSeries: $selectedSeries
        )
        .frame(height: 250)
        
        // Medium Chart - 75% Width
        ChartView(
          data: allData,
          title: "Medium Chart (75%)",
          selectedPoint: $selectedPoint,
          selectedSeries: $selectedSeries
        )
        .frame(width: UIScreen.main.bounds.width * 0.75, height: 250)
        
        // Small Chart - 50% Width
        ChartView(
          data: allData,
          title: "Small Chart (50%)",
          selectedPoint: $selectedPoint,
          selectedSeries: $selectedSeries
        )
        .frame(width: UIScreen.main.bounds.width * 0.5, height: 250)
      }
      .padding()
    }
  }
}

struct ChartView: View {
  let data: [DataPoint]
  let title: String
  @Binding var selectedPoint: DataPoint?
  @Binding var selectedSeries: String?
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      
      Chart {
        ForEach(data) { point in
          LineMark(
            x: .value("Index", point.x),
            y: .value("Value", point.y)
          )
          .foregroundStyle(by: .value("Series", point.series))
          .opacity(selectedSeries == nil || selectedSeries == point.series ? 1 : 0.2)
        }
        
        if let selectedPoint {
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
      .chartYScale(domain: -12...12)
      .chartXScale(domain: 0...100)
      .chartLegend(position: .bottom)
      .frame(height: 200)
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
              DragGesture()
                .onChanged { value in
                  let xPosition = value.location.x
                  let x = proxy.value(atX: xPosition, as: Double.self) ?? 0
                  let filteredData = selectedSeries == nil ? data : data.filter { $0.series == selectedSeries }
                  
                  selectedPoint = filteredData.min(by: { abs($0.x - x) < abs($1.x - x) })
                }
                .onEnded { _ in
                  selectedPoint = nil
                }
            )
        }
      }
      
      if let selectedPoint {
        HStack {
          Text(String(format: "X: %.0f", selectedPoint.x))
          Text(String(format: "Y: %.2f", selectedPoint.y))
          Text(selectedPoint.series)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      
      // Series Legend with interaction
      HStack(spacing: 16) {
        ForEach(["Sine Wave", "Cosine Wave"], id: \.self) { series in
          Button(action: {
            if selectedSeries == series {
              selectedSeries = nil
            } else {
              selectedSeries = series
            }
          }) {
            HStack(spacing: 4) {
              Circle()
                .fill(series == "Sine Wave" ? Color.blue : Color.purple)
                .frame(width: 8, height: 8)
              Text(series)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .opacity(selectedSeries == nil || selectedSeries == series ? 1 : 0.5)
        }
      }
      .padding(.top, 4)
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.white)
        .shadow(radius: 2)
    )
  }
}

#Preview {
  ContentView()
}
