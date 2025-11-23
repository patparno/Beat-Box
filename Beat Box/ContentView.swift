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
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?
    @State private var isPlaying = false
    
    // Add your MP3 filenames here (without extension)
    let soundOptions = ["kick1", "kick2", "snare"]
    @State private var selectedSound = "kick1"
    
    var body: some View {
        VStack(spacing: 30) {
            // Drum icon
            Image(systemName: "music.note")
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.blue)
                .ignoresSafeArea()
            
            // BPM label
            Text("BPM: \(Int(bpm))")
                .font(.title)
                .foregroundColor(.white)
            
            // Slider
            Slider(value: $bpm, in: 40...240, step: 1)
                .onChange(of: bpm) {
                    if isPlaying { restartTimer() }
                }
                .accentColor(.white)
            
            // Sound picker
            Picker("Sound", selection: $selectedSound) {
                ForEach(soundOptions, id: \.self) { sound in
                    Text(sound.capitalized)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedSound) {
                loadSound(named: selectedSound)
            }
            .foregroundColor(.white)
            
            // Start/Stop toggle button
            Button(action: {
                isPlaying.toggle()
                if isPlaying {
                    restartTimer()
                } else {
                    timer?.invalidate()
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
        .background(Color.blue) // coloured background
        .onAppear {
            setupAudio()
            loadSound(named: selectedSound)
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    func loadSound(named: String) {
        if let url = Bundle.main.url(forResource: named, withExtension: "mp3") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } else {
            print("\(named).mp3 not found in bundle")
        }
    }
    
    func restartTimer() {
        timer?.invalidate()
        let interval = 60.0 / bpm
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        }
    }
    
}

