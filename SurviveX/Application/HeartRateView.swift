import SwiftUI
import Foundation

struct HeartRateView: View {
    @State private var currentHeartRate: Double = 0
    @State private var heartRates: [Double] = []
    @State private var currentIndex: Int = 0
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 20) {
            // Static heart image
            Image(systemName: "heart.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundColor(.red)
            
            // Heart rate text that updates
            Text("\(Int(currentHeartRate)) BPM")
                .font(.system(size: 36, weight: .bold))
        }
        .onAppear {
            // Initialize with your heart rate data
            heartRates = [68.18, 54.05, 44.77, 90.90, 60.00, 56.07, 73.17, 52.17, 56.60, 80.00, 55.04, 55.55, 92.30, 65.21, 86.95, 89.55]
            currentHeartRate = heartRates[0]
        }
        .onReceive(timer) { _ in
            // Cycle to next heart rate
            currentIndex = (currentIndex + 1) % heartRates.count
            currentHeartRate = heartRates[currentIndex]
        }
    }
}
