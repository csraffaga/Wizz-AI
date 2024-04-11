//  Wizz-AI
//
//  Created by Gabriel on 4/10/24.
//

import SwiftUI
import CoreMotion
import Foundation

// ViewModel to manage the accelerometer
class MotionManager: ObservableObject {
    private var motionManager: CMMotionManager

    // Published properties that the ContentView can observe
    @Published var x: Double = 0.0
    @Published var y: Double = 0.0
    @Published var z: Double = 0.0

    init() {
        self.motionManager = CMMotionManager()
        self.motionManager.accelerometerUpdateInterval = 1/60 // 60 Hz
    }
    
    func startAccelerometer() {
        // Check if the accelerometer is available before trying to start updates
        guard motionManager.isAccelerometerAvailable else { return }
        
        // Start the accelerometer updates
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            // Make sure there is data, otherwise return
            guard let data = data, error == nil else { return }
            
            // Update the published properties with the new data
            DispatchQueue.main.async {
                self?.x = data.acceleration.x
                self?.y = data.acceleration.y
                self?.z = data.acceleration.z
            }
        }
    }
    
    func stopAccelerometer() {
        motionManager.stopAccelerometerUpdates()
    }
}

extension MotionManager {
    func sendDataToServer() {
        guard let url = URL(string: "http://yourserver.com/process") else { return }

        // Prepare your accelerometer data
        let data = [
            "x": self.x,
            "y": self.y,
            "z": self.z
        ]

        // Convert your data to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return }

        // Create a URLRequest and set its HTTP method to POST
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach your JSON data to the request
        request.httpBody = jsonData

        // Create a URLSession data task to send the data
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            // Handle the response here
            guard let data = data, error == nil else { return }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Optionally handle the response JSON if your server sends back a result
                if let result = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print(result)
                }
            }
        }

        task.resume()  // Start the data task
    }
}



struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    
    var body: some View {
        VStack {
            Text("Accelerometer Data")
            Text("X: \(motionManager.x)")
            Text("Y: \(motionManager.y)")
            Text("Z: \(motionManager.z)")
        }
        .onAppear {
            motionManager.startAccelerometer()
        }
        .onDisappear {
            motionManager.stopAccelerometer()
        }
        .padding()
    }
}

// Replace the preview provider if you have one
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
