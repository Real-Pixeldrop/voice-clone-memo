import Foundation
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var permissionDenied = false
    @Published var isPulsing = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentRecordingURL: URL?
    private var pulseTimer: Timer?

    var recordingURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceCloneMemo")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        // Unique filename to avoid overwriting previous recordings
        return appDir.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")
    }

    func startRecording() {
        // Permission is requested at app launch (AppDelegate).
        // Here we just check status - no dialog will appear.
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            beginRecording()
        } else if status == .notDetermined {
            // Shouldn't happen (requested at launch), but handle gracefully
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.beginRecording() }
                    else { self?.permissionDenied = true }
                }
            }
        } else {
            permissionDenied = true
        }
    }

    private func beginRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        let url = recordingURL
        currentRecordingURL = url

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingTime = 0
            isPulsing = true
            // Update time every second (smoother UI)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                self.recordingTime = self.audioRecorder?.currentTime ?? self.recordingTime + 1
            }
            // Pulse animation toggle
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                self?.isPulsing.toggle()
            }
        } catch {
            print("Recording failed: \(error)")
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        timer?.invalidate()
        pulseTimer?.invalidate()
        isRecording = false
        isPulsing = false
        return currentRecordingURL
    }

    var lastRecordingURL: URL? {
        return currentRecordingURL
    }
}
