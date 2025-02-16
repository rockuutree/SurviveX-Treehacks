import SwiftUI
import Foundation

class HeartRateMonitor: ObservableObject {
    @Published var currentHeartRate: Double = 0.0
    private var timer: Timer?
    private let sampleRate = 100.0
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Update every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateHeartRate()
        }
    }
    
    private func updateHeartRate() {
        if let csvData = readCSV(fileName: "irregular_418.csv"),
           let ppgData = extractPPGData(from: csvData, columnName: "green") {
            let newHeartRate = computeHeartRate(ppgData: ppgData, sampleRate: sampleRate)
            DispatchQueue.main.async {
                self.currentHeartRate = newHeartRate
            }
        }
    }
    
    private func readCSV(fileName: String) -> [[String]]? {
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            print("File not found")
            return nil
        }
        
        do {
            let data = try String(contentsOf: fileURL, encoding: .utf8)
            let rows = data.components(separatedBy: "\n").map { $0.components(separatedBy: ",") }
            return rows
        } catch {
            print("Error reading CSV: \(error)")
            return nil
        }
    }
    
    private func extractPPGData(from csvData: [[String]], columnName: String) -> [Double]? {
        guard let header = csvData.first else { return nil }
        guard let columnIndex = header.firstIndex(of: columnName) else {
            print("Column \(columnName) not found.")
            return nil
        }
        
        return csvData.dropFirst().compactMap { row in
            guard row.count > columnIndex, let value = Double(row[columnIndex]) else {
                return nil
            }
            return value
        }
    }
    
    private func detectPeaks(ppgData: [Double], sampleRate: Double) -> [Int] {
        var peaks: [Int] = []
        let threshold = (ppgData.max() ?? 0) * 0.6 // Adaptive threshold
        
        for i in 1..<ppgData.count - 1 {
            if ppgData[i] > threshold && ppgData[i] > ppgData[i - 1] && ppgData[i] > ppgData[i + 1] {
                peaks.append(i)
            }
        }
        return peaks
    }
    
    private func computeHeartRate(ppgData: [Double], sampleRate: Double) -> Double {
        let peaks = detectPeaks(ppgData: ppgData, sampleRate: sampleRate)
        guard peaks.count > 1 else { return 0.0 }
        
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let timeDiff = Double(peaks[i] - peaks[i - 1]) / sampleRate
            intervals.append(timeDiff)
        }
        
        let averageIBI = intervals.reduce(0, +) / Double(intervals.count)
        return round(60.0 / averageIBI) // Convert to BPM and round to nearest integer
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct HeartView: View {
    @StateObject private var heartRateMonitor = HeartRateMonitor()
    
    var body: some View {
        VStack {
            Image(systemName: "heart.fill")
                .resizable()
                .frame(width: 40, height: 36)
                .foregroundColor(.red)
            
            Text("\(Int(heartRateMonitor.currentHeartRate))")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
        }
        .padding(.top, 40)
        .padding(.leading, 32)
    }
}

#Preview {
    HeartView()
}
