// BeatEngine


import Foundation
import AVFoundation

class BeatEngine: ObservableObject {
    @Published var bpm: Double = 120 {
        didSet { restartTimerIfNeeded() }
    }
    @Published var isPlaying = false

    // 16‑step patterns (true = play on that step)
    @Published var kickPattern  = Array(repeating: false, count: 16)
    @Published var snarePattern = Array(repeating: false, count: 16)
    @Published var tomPattern   = Array(repeating: false, count: 16)

    private let engine = AVAudioEngine()
    private let kickPlayer  = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let tomPlayer   = AVAudioPlayerNode()

    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var tomBuffer: AVAudioPCMBuffer?

    private var stepTimer: DispatchSourceTimer?
    private let stepsPerBeat = 4        // 16‑th note grid
    private var currentStep = 0         // 0...15

    init() {
        engine.attach(kickPlayer)
        engine.attach(snarePlayer)
        engine.attach(tomPlayer)

        // Force a mono path to match your mono buffers
        let sampleRate: Double = 44100
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        engine.connect(kickPlayer,  to: engine.mainMixerNode, format: monoFormat)
        engine.connect(snarePlayer, to: engine.mainMixerNode, format: monoFormat)
        engine.connect(tomPlayer,   to: engine.mainMixerNode, format: monoFormat)

        try? engine.start()
    }

    // MARK: - Loading sounds

    func loadKick(named: String) {
        kickBuffer = loadBuffer(named: named)
    }

    func loadSnare(named: String) {
        snareBuffer = loadBuffer(named: named)
    }

    func loadTom(named: String) {
        tomBuffer = loadBuffer(named: named)
    }

    private func loadBuffer(named: String) -> AVAudioPCMBuffer? {
        if named == "click" {
            return generateClickBuffer()
        }

        guard let url = Bundle.main.url(forResource: named, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url)
        else {
            print("Failed to load \(named)")
            return nil
        }

        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            print("Failed to create buffer for \(named)")
            return nil
        }

        try? file.read(into: buffer)
        return buffer
    }

    private func generateClickBuffer() -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let duration: Double = 0.01   // 10 ms click
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            ptr[i] = Float(exp(-t * 2000))   // sharp transient
        }

        return buffer
    }

    // MARK: - Transport

    func start() {
        guard kickBuffer != nil || snareBuffer != nil || tomBuffer != nil else {
            print("No buffers loaded")
            return
        }

        isPlaying = true
        currentStep = 0

        kickPlayer.play()
        snarePlayer.play()
        tomPlayer.play()

        startTimer()
    }

    func stop() {
        isPlaying = false
        stepTimer?.cancel()
        stepTimer = nil

        kickPlayer.stop()
        snarePlayer.stop()
        tomPlayer.stop()
    }

    private func restartTimerIfNeeded() {
        if isPlaying {
            stepTimer?.cancel()
            stepTimer = nil
            startTimer()
        }
    }

    private func startTimer() {
        let intervalSeconds = (60.0 / bpm) / Double(stepsPerBeat)   // 16th‑note steps

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.advanceStep()
        }
        stepTimer = timer
        timer.resume()
    }

    private func advanceStep() {
        guard isPlaying else { return }

        // Capture current step and buffers safely
        let step = currentStep
        currentStep = (currentStep + 1) % 16

        // Fire the step on the audio queue
        if kickPattern[step], let buf = kickBuffer {
            kickPlayer.scheduleBuffer(buf, at: nil, options: [])
        }
        if snarePattern[step], let buf = snareBuffer {
            snarePlayer.scheduleBuffer(buf, at: nil, options: [])
        }
        if tomPattern[step], let buf = tomBuffer {
            tomPlayer.scheduleBuffer(buf, at: nil, options: [])
        }
    }
}
