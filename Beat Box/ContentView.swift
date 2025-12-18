//
//  ContentView.swift
//  Beat Box
//
//  Created by Patrick Parno on 2025-11-23.
//
import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var bpm: Double = 120
    @State private var isPlaying = false
    
    // Audio engine
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    
    @State private var audioFile: AVAudioFile?
    
    // Default bundled sounds
    @State private var soundOptions = ["kick1", "snare1", "tom1"]
    @State private var selectedSound = "kick1"
    
    var body: some View {
        VStack(spacing: 30) {
            Text("BPM: \(Int(bpm))")
                .font(.title)
                .foregroundColor(.white)
            
            Slider(value: $bpm, in: 40...240, step: 1)
                .accentColor(.white)
                .onChange(of: bpm) {
                    if isPlaying {
                        varispeed.rate = Float(bpm / 120.0)
                    }
                }
            
            Picker("Sound", selection: $selectedSound) {
                ForEach(soundOptions, id: \.self) { sound in
                    Text(sound.capitalized)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedSound) {
                loadSound(named: selectedSound)
                if isPlaying { startBeat() }
            }
            .foregroundColor(.white)
            
            Button(action: {
                isPlaying.toggle()
                if isPlaying {
                    startBeat()
                } else {
                    player.stop()
                }
            }) {
                Text(isPlaying ? "Stop" : "Start")
                    .font(.headline)
                    .padding()
                    .frame(width: 120)
                    .background(Color.white)
                    .foregroundColor(.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.blue)
        .onAppear {
            setupAudio()
            loadSound(named: selectedSound)
        }
        .onDisappear {
            player.stop()
            engine.stop()
        }
    }
    
    func setupAudio() {
        engine.attach(player)
        engine.attach(varispeed)
        
        // ✅ Force mono format (44.1 kHz, 1 channel)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        
        try? engine.start()
    }
    
    func loadSound(named: String) {
        if let url = Bundle.main.url(forResource: named, withExtension: "wav") {
            audioFile = try? AVAudioFile(forReading: url)
        } else {
            print("\(named) not found")
        }
        
        if let file = audioFile {
            let format = file.processingFormat
            print("Loaded \(named): sampleRate=\(format.sampleRate), channels=\(format.channelCount)")
        }
    }
    
    func startBeat() {
        guard let file = audioFile else {
            print("No audio file loaded")
            return
        }
        player.stop()
        file.framePosition = 0
        
        let fileFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frames) else {
            print("Failed to create input buffer")
            return
        }
        try? file.read(into: inBuffer)
        
        if let channelData = inBuffer.floatChannelData?[0] {
            let samples = UnsafeBufferPointer(start: channelData, count: Int(inBuffer.frameLength))
            let maxAmp = samples.max() ?? 0
            print("Kick1 max amplitude: \(maxAmp)")
        }
        
        print("=== Debug Info ===")
        print("Engine running? \(engine.isRunning)")
        print("File length: \(file.length)")
        print("File format: sampleRate=\(fileFormat.sampleRate), channels=\(fileFormat.channelCount)")
        print("Input buffer frameLength: \(inBuffer.frameLength)")
        
        // Ensure engine is running
        if !engine.isRunning {
            do {
                try engine.start()
                print("Engine started successfully")
            } catch {
                print("Engine failed to start: \(error)")
            }
        }
        
        // Force mono conversion
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: fileFormat.sampleRate, channels: 1)!
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frames) else {
            print("Failed to create output buffer")
            return
        }
        guard let converter = AVAudioConverter(from: fileFormat, to: monoFormat) else {
            print("Failed to create converter")
            return
        }
        
        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumed = true
            return inBuffer
        }
        
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { print("Conversion error: \(error)") }
        
        print("Output buffer frameLength: \(outBuffer.frameLength)")
        
        // Schedule and play
        player.scheduleBuffer(outBuffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        print("Player isPlaying after play? \(player.isPlaying)")
        
        varispeed.rate = Float(bpm / 120.0)
        print("Varispeed rate set to \(varispeed.rate)")
    }
}
