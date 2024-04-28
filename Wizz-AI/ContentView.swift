import SwiftUI
import CoreMotion

class MotionViewModel: ObservableObject {
    private var motionManager: CMMotionManager?
    private var timer: Timer?
    private var dataBuffer: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    
    @Published var x: Double = 0
    @Published var y: Double = 0
    @Published var z: Double = 0
    @Published var totalJumps: Int = 0
    
    init() {
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1  // Updates every 0.1 seconds
        startMotionUpdates()
        startSendingData()
    }
    
    func startMotionUpdates() {
        motionManager?.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async {
                self?.updateBuffer(with: data.acceleration)
            }
        }
    }
    
    private func updateBuffer(with acceleration: CMAcceleration) {
        self.x = acceleration.x
        self.y = acceleration.y
        self.z = acceleration.z
        
        // Append data with timestamp
        dataBuffer.append((x: acceleration.x, y: acceleration.y, z: acceleration.z, timestamp: Date()))
        
        // Remove data older than 5 seconds (since we're now sending every 5 seconds)
        let thresholdDate = Date().addingTimeInterval(-5)
        dataBuffer = dataBuffer.filter { $0.timestamp > thresholdDate }
    }
    
    func startSendingData() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendDataToServer()
        }
    }
    
    func sendDataToServer() {
        guard let url = URL(string: "http://10.150.96.212:5001/process") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send the last 5 seconds of data
        let jsonData = dataBuffer.map { ["x": $0.x, "y": $0.y, "z": $0.z] }
        
        guard let httpBody = try? JSONEncoder().encode(jsonData) else {
            print("Error encoding JSON")
            return
        }
        request.httpBody = httpBody
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                guard let data = data else { return }
                do {
                    let jsonResponse = try JSONDecoder().decode([String: Int].self, from: data)
                    DispatchQueue.main.async {
                        self?.totalJumps = jsonResponse["jumps_per_minute"] ?? 0
                    }
                } catch {
                    print("Error decoding response: \(error)")
                }
            }
        }.resume()
    }
}

struct ContentView: View {
    @StateObject private var motionViewModel = MotionViewModel()
    
    var body: some View {
        VStack {
            Text("X: \(motionViewModel.x, specifier: "%.2f")")
            Text("Y: \(motionViewModel.y, specifier: "%.2f")")
            Text("Z: \(motionViewModel.z, specifier: "%.2f")")
            Text("Jumps per Minute: \(motionViewModel.totalJumps)")
                .padding()
                .font(.title)
        }
        .padding()
    }
}
