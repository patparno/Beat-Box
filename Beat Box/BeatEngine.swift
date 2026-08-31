// BeatEngine


import Foundation
import AVFoundation
import QuartzCore
import Darwin

class BeatEngine: ObservableObject {
    @Published var bpm: Double = 120 { didSet { persistState() } }
    @Published var isPlaying = false

    // Currently sounding step, synced to actual playback time (-1 when stopped)
    @Published var currentStep = -1

    // 16‑step patterns (true = play on that step)
    @Published var kickPattern  = Array(repeating: false, count: 16) { didSet { persistState() } }
    @Published var snarePattern = Array(repeating: false, count: 16) { didSet { persistState() } }
    @Published var tomPattern   = Array(repeating: false, count: 16) { didSet { persistState() } }

    // Per‑track sound selection
    @Published var kickSound  = "kick1"  { didSet { loadKick(named: kickSound);   persistState() } }
    @Published var snareSound = "snare1" { didSet { loadSnare(named: snareSound); persistState() } }
    @Published var tomSound   = "tom1"   { didSet { loadTom(named: tomSound);     persistState() } }

    private let engine = AVAudioEngine()
    private let kickPlayer  = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let tomPlayer   = AVAudioPlayerNode()

    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var tomBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 44100
    private let stepsPerBeat = 4        // 16‑th note grid

    // MARK: - Lookahead scheduler state
    // Pattern adapted from the classic "tale of two clocks" Web Audio scheduling
    // technique: a frequent, cheap timer looks ahead a short window and schedules
    // any audio events (and matching UI updates) that fall inside it against the
    // engine's own sample clock, rather than firing playback directly off a timer.
    private var schedulerTimer: DispatchSourceTimer?
    private let schedulerIntervalSeconds: Double = 0.02   // how often we look ahead
    private let scheduleAheadSeconds: Double = 0.1         // how far ahead we schedule

    private var nextStepToSchedule = 0
    private var nextStepSampleTime: AVAudioFramePosition = 0
    private var anchorSampleTime: AVAudioFramePosition = 0
    private var anchorHostSeconds: CFTimeInterval = 0
    private var playbackSession = 0

    /// The engine output's *actual* hardware sample rate, which is what
    /// `engine.outputNode.lastRenderTime.sampleTime` counts in - not
    /// necessarily the `sampleRate` constant above, which only describes the
    /// bundled audio files' format. These can differ (e.g. a real device's
    /// active route reporting 24kHz while our WAV files are 44.1kHz); mixing
    /// the two up when computing AVAudioTime for scheduling silently placed
    /// every buffer at the wrong point on the real output timeline - no
    /// crash, no error, just nothing audible, and only on real hardware,
    /// since the Simulator's virtual output happened to already be 44.1kHz.
    private var outputSampleRate: Double {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        return rate > 0 ? rate : sampleRate
    }

    /// `AVAudioTime(sampleTime:atRate:)` scheduling turned out to be a real
    /// bug, not just a display-only concern: on a real device it silently
    /// dropped every buffer (confirmed via a mixer tap showing true digital
    /// silence, even while `scheduleBuffer` was being called with valid
    /// buffers and no error). Sample time is only unambiguous when the value
    /// and the node consuming it agree on which node's render-relative
    /// timeline it's counted against; host time sidesteps that entirely -
    /// it's one absolute wall-clock reference every node agrees on - so
    /// scheduling is now done from `wallClockSeconds` converted to raw host
    /// ticks, not from sample counts.
    private static let hostTicksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return 1_000_000_000 * Double(info.denom) / Double(info.numer)
    }()

    private func hostTime(fromSeconds seconds: Double) -> UInt64 {
        UInt64(max(seconds, 0) * Self.hostTicksPerSecond)
    }

    // Suppresses persistState() while restoreState() is assigning properties
    // one at a time. Without this, the first property restored (e.g. bpm)
    // would trigger a save that writes back the *other* properties' still-
    // default in-memory values, clobbering their saved data on disk before
    // restoreState() gets a chance to read it.
    private var isRestoring = false

    init() {
        engine.attach(kickPlayer)
        engine.attach(snarePlayer)
        engine.attach(tomPlayer)

        // Force a mono path to match your mono buffers
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        engine.connect(kickPlayer,  to: engine.mainMixerNode, format: monoFormat)
        engine.connect(snarePlayer, to: engine.mainMixerNode, format: monoFormat)
        engine.connect(tomPlayer,   to: engine.mainMixerNode, format: monoFormat)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        do {
            try engine.start()
        } catch {
            print("engine.start() failed: \(error)")
        }

        restoreState()
    }

    // MARK: - Persistence

    private enum DefaultsKey {
        static let bpm          = "beatbox.bpm"
        static let kickPattern  = "beatbox.kickPattern"
        static let snarePattern = "beatbox.snarePattern"
        static let tomPattern   = "beatbox.tomPattern"
        static let kickSound    = "beatbox.kickSound"
        static let snareSound   = "beatbox.snareSound"
        static let tomSound     = "beatbox.tomSound"
    }

    private func persistState() {
        guard !isRestoring else { return }
        let defaults = UserDefaults.standard
        defaults.set(bpm, forKey: DefaultsKey.bpm)
        // Bool arrays round-trip through UserDefaults/a plist as plain 0/1
        // integers, so reading them back with `as? [Bool]` silently fails.
        // JSON-encoding sidesteps that ambiguity entirely.
        defaults.set(try? JSONEncoder().encode(kickPattern), forKey: DefaultsKey.kickPattern)
        defaults.set(try? JSONEncoder().encode(snarePattern), forKey: DefaultsKey.snarePattern)
        defaults.set(try? JSONEncoder().encode(tomPattern), forKey: DefaultsKey.tomPattern)
        defaults.set(kickSound, forKey: DefaultsKey.kickSound)
        defaults.set(snareSound, forKey: DefaultsKey.snareSound)
        defaults.set(tomSound, forKey: DefaultsKey.tomSound)
    }

    /// UserDefaults writes are cached in-process and flushed to disk on the
    /// system's own schedule, which isn't guaranteed to happen before the app
    /// is killed. Call this when the app is about to leave the foreground
    /// (scenePhase -> .background) to force the pending writes to disk so a
    /// swipe-to-quit right after editing a pattern doesn't lose it.
    func flushPersistedState() {
        UserDefaults.standard.synchronize()
    }

    /// Restores the last saved beat, if any. Sound selections are always
    /// (re-)assigned, even absent saved data, since their didSet is what
    /// actually loads the sample buffers for playback.
    private func restoreState() {
        isRestoring = true
        defer { isRestoring = false }

        let defaults = UserDefaults.standard

        if defaults.object(forKey: DefaultsKey.bpm) != nil {
            bpm = defaults.double(forKey: DefaultsKey.bpm)
        }
        if let data = defaults.data(forKey: DefaultsKey.kickPattern),
           let saved = try? JSONDecoder().decode([Bool].self, from: data), saved.count == 16 {
            kickPattern = saved
        }
        if let data = defaults.data(forKey: DefaultsKey.snarePattern),
           let saved = try? JSONDecoder().decode([Bool].self, from: data), saved.count == 16 {
            snarePattern = saved
        }
        if let data = defaults.data(forKey: DefaultsKey.tomPattern),
           let saved = try? JSONDecoder().decode([Bool].self, from: data), saved.count == 16 {
            tomPattern = saved
        }

        kickSound  = defaults.string(forKey: DefaultsKey.kickSound)  ?? kickSound
        snareSound = defaults.string(forKey: DefaultsKey.snareSound) ?? snareSound
        tomSound   = defaults.string(forKey: DefaultsKey.tomSound)   ?? tomSound
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
        guard !isPlaying else { return }

        // Anchor "now" in both the engine's sample timeline and wall-clock (host)
        // time so future steps can be converted between the two consistently.
        guard let renderTime = engine.outputNode.lastRenderTime, renderTime.isSampleTimeValid else {
            print("Engine not rendering yet; can't anchor scheduler")
            return
        }

        playbackSession += 1
        isPlaying = true
        currentStep = -1

        anchorSampleTime = renderTime.sampleTime
        anchorHostSeconds = CACurrentMediaTime()
        nextStepSampleTime = anchorSampleTime
        nextStepToSchedule = 0

        kickPlayer.play()
        snarePlayer.play()
        tomPlayer.play()

        startSchedulerTimer()
    }

    func stop() {
        isPlaying = false
        currentStep = -1
        schedulerTimer?.cancel()
        schedulerTimer = nil

        kickPlayer.stop()
        snarePlayer.stop()
        tomPlayer.stop()
    }

    private func startSchedulerTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: schedulerIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.scheduleAheadIfNeeded()
        }
        schedulerTimer = timer
        timer.resume()
    }

    /// Schedules every step whose sample time falls within the lookahead window,
    /// using the current bpm at the moment each step is scheduled. Because bpm is
    /// read live here (not baked into a fixed timer interval), changing tempo
    /// mid-playback smoothly changes the spacing of future steps with no restart
    /// or stutter.
    private func scheduleAheadIfNeeded() {
        guard isPlaying else { return }

        let session = playbackSession
        let outputRate = outputSampleRate
        let samplesPerStep = (60.0 / bpm) / Double(stepsPerBeat) * outputRate

        guard let renderTime = engine.outputNode.lastRenderTime, renderTime.isSampleTimeValid else { return }
        let scheduleUntilSampleTime = renderTime.sampleTime + AVAudioFramePosition(scheduleAheadSeconds * outputRate)

        while nextStepSampleTime < scheduleUntilSampleTime {
            scheduleStep(nextStepToSchedule, atSampleTime: nextStepSampleTime, outputRate: outputRate, session: session)

            nextStepToSchedule = (nextStepToSchedule + 1) % 16
            nextStepSampleTime += AVAudioFramePosition(samplesPerStep)
        }
    }

    private func scheduleStep(_ step: Int, atSampleTime sampleTime: AVAudioFramePosition, outputRate: Double, session: Int) {
        let secondsFromAnchor = Double(sampleTime - anchorSampleTime) / outputRate
        let wallClockSeconds = anchorHostSeconds + secondsFromAnchor
        let when = AVAudioTime(hostTime: hostTime(fromSeconds: wallClockSeconds))

        if kickPattern[step], let buf = kickBuffer {
            kickPlayer.scheduleBuffer(buf, at: when, options: [])
        }
        if snarePattern[step], let buf = snareBuffer {
            snarePlayer.scheduleBuffer(buf, at: when, options: [])
        }
        if tomPattern[step], let buf = tomBuffer {
            tomPlayer.scheduleBuffer(buf, at: when, options: [])
        }

        // Drive the visual playhead off the same wall-clock time so it lines
        // up with what's actually audible, rather than off the scheduler's
        // own (much coarser and jittery) timer interval.
        let deadline = DispatchTime(uptimeNanoseconds: UInt64(max(wallClockSeconds, 0) * 1_000_000_000))

        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self, self.isPlaying, self.playbackSession == session else { return }
            self.currentStep = step
        }
    }
}
