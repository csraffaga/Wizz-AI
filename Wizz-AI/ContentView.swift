import SwiftUI
import CoreMotion
import AVFoundation

// Server response structure, needed to decode all data processed in the server
struct ServerResponse: Decodable {
    var jumps_per_minute: Int
    var song_path: String?
    var song_name: String?
    var song_artist: String?
    var song_cover_path: String?
}

// AudioViewModel is responsible for gathering audio cues during jump roping session
class AudioViewModel: ObservableObject {
    var audioRecorder: AVAudioRecorder?
    var uploadTimer: Timer?
    
    func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set up the audio session for both playback and recording.
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                print("Permission granted")
            } else {
                print("Permission denied")
            }
        }
    }
    
    
    func setupAudioRecorder() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("recordedAudio.m4a")
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            print("Audio recorder setup failed: \(error)")
        }
    }
    
    func startRecording() {
        guard let recorder = audioRecorder else {
            print("Audio Recorder not set up")
            return
        }
        if !recorder.isRecording {
            recorder.record()
            print("Recording started")
        }
    }
    
    func stopRecording() {
        guard let recorder = audioRecorder else {
            print("Audio Recorder not set up")
            return
        }
        if recorder.isRecording {
            recorder.stop()
            print("Recording stopped")
            uploadAudioFile() // Uploads the file after we stop the recording
        }
    }
    
    // Upload the filer to the server. Note: the server here denotes the last testing session, this must be changed when testing it in new envrionments
    func uploadAudioFile() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("recordedAudio.m4a")
        
        guard let url = URL(string: "http://http://10.150.53.192:5006/upload") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recordedAudio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        if let audioData = try? Data(contentsOf: fileURL) {
            body.append(audioData)
        }
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                return
            }
            if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                print("File uploaded successfully!")
            }
        }.resume()
    }
}

// MotionViewModel is responsible for encapsulating accelerometer information into packages sent for analysis to the server, and gathering back feedback from the server to display the calculated jumps per minute and the song that most closely matches this value.
class MotionViewModel: ObservableObject {
    private var motionManager: CMMotionManager?
    private var timer: Timer?
    private var dataBuffer: [(x: Double, y: Double, z: Double, timestamp: Date)] = []
    private var configuration = URLSessionConfiguration.background(withIdentifier: "com.WizzAi.identifier")
    
    // Create initial, gloval variables necessary for implementation
    
    @Published var x: Double = 0
    @Published var y: Double = 0
    @Published var z: Double = 0
    @Published var totalJumps: Int = 0
    @Published var songName: String = "Unknown Song"
    @Published var songArtist: String = "Unknown Artist"
    @Published var songCoverPath: String = ""
    @Published var songCover: UIImage?
    
    var audioPlayer: AVPlayer?
    private var currentSongPath: String?
    
    // Load initial functions
    init() {
        configuration.isDiscretionary = true
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1
        startMotionUpdates()
        startSendingData()
        setupAudioSession()
        preloadAudioPlayer()
    }
    
    func startMotionUpdates() {
        motionManager?.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let data = data, error == nil else { return }
            DispatchQueue.global(qos: .background).async {
                self?.updateBuffer(with: data.acceleration)
            }
        }
    }
    
    // Update 7.5 second sliding window in the buffer
    private func updateBuffer(with acceleration: CMAcceleration) {
        DispatchQueue.main.async {
            self.x = acceleration.x
            self.y = acceleration.y
            self.z = acceleration.z
            self.dataBuffer.append((x: acceleration.x, y: acceleration.y, z: acceleration.z, timestamp: Date()))
            let thresholdDate = Date().addingTimeInterval(-7.5)
            self.dataBuffer = self.dataBuffer.filter { $0.timestamp > thresholdDate }
        }
    }
    
    func startSendingData() {
        timer = Timer.scheduledTimer(withTimeInterval: 7.5, repeats: true) { [weak self] _ in
            self?.sendDataToServer()
        }
    }
    
    // Function responsible for sending accelerometer information to the server
    func sendDataToServer() {
        
        guard let url = URL(string: "http://10.150.53.192:5006/process") else { return }
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
                        if let songName = jsonResponse.song_name, self?.songName != songName {
                            self?.songName = songName
                        }
                        if let songArtist = jsonResponse.song_artist, self?.songArtist != songArtist {
                            self?.songArtist = songArtist
                        }
                        // Check if the song path has changed before deciding to change the track
                        if let songPath = jsonResponse.song_path, self?.currentSongPath != songPath {
                            self?.playSong(atPath: songPath)
                            self?.currentSongPath = songPath
                        }
                        if let coverPath = jsonResponse.song_cover_path, let url = URL(string: coverPath) {
                            self?.loadImage(from: url)
                        }
                    }
                } catch {
                    print("Error decoding response: \(error)")
                }
            }
        }.resume()
    }
    
    // Function responsible for retrieving accelerometer information from the server
    func fetchJumpsPerMinute() {
        guard let url = URL(string: "http://10.150.53.192:5006/get_jpm") else { return }
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
                            self?.currentSongPath = songPath
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
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer?.replaceCurrentItem(with: playerItem)
            self?.audioPlayer?.play()
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let imageData = data else { return }
            DispatchQueue.global(qos: .background).async {
                let img = UIImage(data: imageData)
                DispatchQueue.main.async {
                    self?.songCover = img
                }
            }
        }.resume()
    }
    
    // This function is placed entirely for performance enhancing. It preloads an audio file so that when the user is first given a song that matches their jumps, it does not take a delay to plah it.
    private func preloadAudioPlayer() {
        guard let url = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3") else { return }
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        audioPlayer?.pause() // Ensure we don't start playing it yet!
    }
    
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
    @State private var isActive = false
    
    var body: some View {
        ZStack {
            MainView()
                .opacity(isActive ? 1 : 0)
            SplashScreenView()
                .opacity(isActive ? 0 : 1)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 2)) {
                    self.isActive = true
                }
            }
        }
    }
}

// Loading animation with the icon of our app
struct SplashScreenView: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
            GradientText(text: "Wizz-AI", colorScheme: colorScheme)
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct GradientText: View {
    let text: String
    let colorScheme: ColorScheme
    
    var body: some View {
        Text(text)
            .foregroundColor(.clear)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark ? [Color.white, Color.gray] : [Color.black, Color.gray]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(Text(text)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                )
            )
    }
}

// Animation which has a sine wave matched to the frequency of the current JPM
struct SineWave: Shape {
    var frequency: Double
    var phase: Double
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(frequency, phase) }
        set {
            frequency = newValue.first
            phase = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude = rect.height / 4
        let waveLength = rect.width / CGFloat(frequency)
        let horizontalOffset: CGFloat = 20
        
        path.move(to: CGPoint(x: horizontalOffset, y: rect.midY))
        
        for x in stride(from: horizontalOffset, to: rect.width - horizontalOffset, by: 1) {
            let y = frequency == 0 ? rect.midY : amplitude * sin((2 * .pi / waveLength) * x + CGFloat(phase)) + rect.midY
            if x > horizontalOffset + 1 {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

// UI implementation in three main vertical stacks: JPM visualization, sine wave animation, and finally song information with a mute button for better usability at the bottom
struct MainView: View {
    @StateObject private var motionViewModel = MotionViewModel()
    @StateObject private var audioViewModel = AudioViewModel()
    @State private var targetJumpsPerMinute = 160
    @State private var isMuted = false
    @State private var showInfo = false
    @State private var phase: Double = 0
    
    var body: some View {
        VStack {
            Spacer().frame(height: 50)
            
            VStack(spacing: 20) {
                HStack(spacing: 1) {
                    Spacer().frame(width: 6)
                    Text("JPM")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                        .shadow(color: .gray.opacity(0.3), radius: 2, x: 0, y: 2)
                    Spacer().frame(width: 1)
                    Button(action: {
                        showInfo.toggle()
                    }) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showInfo, arrowEdge: .top) {
                        Text("Jumps per Minute")
                            .font(.body)
                            .padding()
                            .frame(maxWidth: 200)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .presentationCompactAdaptation((.popover))
                    }
                }
                .padding(.bottom, 10)
                
                ZStack {
                    Circle()
                        .stroke(lineWidth: 20)
                        .opacity(0.3)
                        .foregroundColor(.blue)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(Double(motionViewModel.totalJumps) / Double(targetJumpsPerMinute), 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                        .foregroundColor(.blue)
                        .rotationEffect(Angle(degrees: 270.0))
                    
                    Text("\(motionViewModel.totalJumps)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .frame(width: 250, height: 250)
                .shadow(radius: 10)
                .animation(.linear, value: motionViewModel.totalJumps)
            }
            .padding(.top, 20)
            .onChange(of: motionViewModel.totalJumps) { newValue in
                // Visual Feedback for Jump Detection
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
            }
            
            Spacer()
            
            // Sine wave animation
            SineWave(frequency: Double(motionViewModel.totalJumps) / 10, phase: phase)
                .stroke(Color.gray, lineWidth: 2)
                .shadow(color: Color.gray.opacity(0.7), radius: 10, x: 0, y: 0)
                .frame(height: 50)
                .padding(.vertical, 20)
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        phase += .pi * 2
                    }
                }
            
            Spacer()
            
            // Song display section at the bottom of the application (last horizontal stack)
            HStack {
                if let image = motionViewModel.songCover {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .cornerRadius(5)
                        .shadow(radius: 5)
                } else {
                    Image("loading")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .cornerRadius(5)
                        .shadow(radius: 5)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(motionViewModel.songName)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(motionViewModel.songArtist)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: {
                    isMuted.toggle()
                    motionViewModel.audioPlayer?.isMuted = isMuted
                }) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding(.bottom, 30)
        }
        .padding()
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 7.5, repeats: true) { _ in
                motionViewModel.fetchJumpsPerMinute()
            }
            audioViewModel.requestMicrophonePermission() // Request permission when the view appears.
            audioViewModel.setupAudioSession()
            audioViewModel.setupAudioRecorder()
            // Stop and start recording to upload audio data every 7.5 seconds
            audioViewModel.stopRecording()
            audioViewModel.startRecording()
        }
        .background(Color(.systemBackground)) // allow dark mode changes in our application
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
