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
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()   // ✅ new node
    
    // Keep audioFile in scope for load/start
    @State private var audioFile: AVAudioFile?
    
    let soundOptions = ["kick1", "kick2", "snare"]
    @State private var selectedSound = "kick1"
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "music.note")
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.blue)
                .ignoresSafeArea()
            
            Text("BPM: \(Int(bpm))")
                .font(.title)
                .foregroundColor(.white)
            
            Slider(value: $bpm, in: 40...240, step: 1)
                .accentColor(.white)
                .onChange(of: bpm) {
                    if isPlaying {
                        varispeed.rate = Float(bpm / 120.0)   // ✅ adjust tempo
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
                if isPlaying { startBeat() } // reload sound if playing
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
        
        // Connect: player → varispeed → mixer
        engine.connect(player, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        
        try? engine.start()
    }
    
    func loadSound(named: String) {
        if let url = Bundle.main.url(forResource: named, withExtension: "mp3") {
            audioFile = try? AVAudioFile(forReading: url)
        } else {
            print("\(named).mp3 not found")
        }
    }
    
    func startBeat() {
        guard let file = audioFile else { return }
        
        // Always stop before rescheduling
        player.stop()
        
        // Rewind the file before reading
        file.framePosition = 0
        
        // Create a new buffer
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                      frameCapacity: AVAudioFrameCount(file.length))!
        try? file.read(into: buffer)
        
        // Schedule buffer again
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        
        // Restart playback
        player.play()
        
        // Apply tempo
        varispeed.rate = Float(bpm / 120.0)
    }
}
