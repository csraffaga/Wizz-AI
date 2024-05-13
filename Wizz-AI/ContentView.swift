import SwiftUI
import CoreMotion
import AVFoundation

// Define a structure to represent the server response
struct ServerResponse: Decodable {
    var jumps_per_minute: Int
    var song_path: String?  // song_path can be optional if not always present
}

class MotionViewModel: ObservableObject {
    private var motionManager: CMMotionManager?
    private var timer: Timer?
    private var dataBuffer: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    
    @Published var x: Double = 0
    @Published var y: Double = 0
    @Published var z: Double = 0
    @Published var totalJumps: Int = 0
    
    // Updated to store AVPlayer as a class property
    private var audioPlayer: AVPlayer?
    private var currentSongPath: String?  // Store the current song path

    init() {
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1  // Updates every 0.1 seconds
        startMotionUpdates()
        startSendingData()
        setupAudioSession()  // Setup the audio session
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
        dataBuffer.append((x: acceleration.x, y: acceleration.y, z: acceleration.z, timestamp: Date()))
        let thresholdDate = Date().addingTimeInterval(-12)
        dataBuffer = dataBuffer.filter { $0.timestamp > thresholdDate }
    }
    
    func startSendingData() {
        timer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
            self?.sendDataToServer()
        }
    }
    
    func sendDataToServer() {
        guard let url = URL(string: "http://10.0.0.209:5001/process") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
                    let jsonResponse = try JSONDecoder().decode(ServerResponse.self, from: data)
                    DispatchQueue.main.async {
                        self?.totalJumps = jsonResponse.jumps_per_minute
                        // Check if the song path has changed before deciding to change the track
                        if let songPath = jsonResponse.song_path, self?.currentSongPath != songPath {
                            self?.playSong(atPath: songPath)
                            self?.currentSongPath = songPath  // Update the current song path
                        }
                    }
                } catch {
                    print("Error decoding response: \(error)")
                }
            }
        }.resume()
    }
    
    func fetchJumpsPerMinute() {
        guard let url = URL(string: "http://10.0.0.209:5001/get_jpm") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                guard let data = data else { return }
                do {
                    let jsonResponse = try JSONDecoder().decode(ServerResponse.self, from: data)
                    DispatchQueue.main.async {
                        self?.totalJumps = jsonResponse.jumps_per_minute
                        // Check if the song path has changed before deciding to change the track
                        if let songPath = jsonResponse.song_path, self?.currentSongPath != songPath {
                            self?.playSong(atPath: songPath)
                            self?.currentSongPath = songPath  // Update the current song path
                        }
                    }
                } catch {
                    print("Error decoding response: \(error)")
                }
            }
        }.resume()
    }

    func playSong(atPath path: String) {
        guard let url = URL(string: path) else {
            print("Invalid song URL")
            return
        }
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        audioPlayer?.play()
    }
    
    // Added function to setup audio session
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
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
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { _ in
                motionViewModel.fetchJumpsPerMinute()
            }
        }
    }
}
