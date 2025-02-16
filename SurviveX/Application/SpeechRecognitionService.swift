import Speech
import AVFoundation

class SpeechRecognitionService: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var currentTranscription: String = ""
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        self.speechRecognizer?.delegate = self
    }
    
    func startRecording() async -> Bool {
        // First check authorization status
        let authStatus = await checkPermissions()
        guard authStatus else {
            print("Speech recognition or microphone access denied")
            return false
        }
        
        // Ensure we're not already running
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            return false
        }
        
        do {
            try await configureAudioSession()
            try await setupRecognition()
            return true
        } catch {
            print("Failed to start recording: \(error)")
            return false
        }
    }
    
    private func checkPermissions() async -> Bool {
        // Check speech recognition authorization
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        // Check microphone authorization
        let micAuth = await withCheckedContinuation { continuation in
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                continuation.resume(returning: true)
            case .denied:
                continuation.resume(returning: false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            @unknown default:
                continuation.resume(returning: false)
            }
        }
        
        return speechAuth && micAuth
    }
    
    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func setupRecognition() async throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognitionService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        try audioEngine.start()
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentTranscription = result.bestTranscription.formattedString
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
    }
    
    func getCurrentTranscription() -> String {
        return currentTranscription
    }
}
