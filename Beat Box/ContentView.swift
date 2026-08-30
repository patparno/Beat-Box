//
//  ContentView.swift
//  Beat Box
//
//  Created by Patrick Parno on 2025-11-23.
//
import SwiftUI

struct ContentView: View {
    @StateObject private var engine = BeatEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            Text("BPM: \(Int(engine.bpm))")
                .font(.title)

            Slider(value: $engine.bpm, in: 40...240, step: 1)
                .padding(.horizontal)

            // 16‑step grid
            VStack(spacing: 16) {
                stepRow(title: "Kick",  pattern: $engine.kickPattern)
                stepRow(title: "Snr", pattern: $engine.snarePattern)
                stepRow(title: "Tom",   pattern: $engine.tomPattern)
            }

            // Sound pickers
            VStack(spacing: 12) {
                soundPickerRow(title: "Kick", selection: $engine.kickSound)
                soundPickerRow(title: "Snr", selection: $engine.snareSound)
                soundPickerRow(title: "Tom", selection: $engine.tomSound)
            }

            HStack(spacing: 16) {
                Button(engine.isPlaying ? "Stop" : "Start") {
                    if engine.isPlaying {
                        engine.stop()
                    } else {
                        engine.start()
                    }
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(engine.isPlaying ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(10)
                .accessibilityIdentifier("startStopButton")

                Button("Clear") {
                    engine.kickPattern = Array(repeating: false, count: 16)
                    engine.snarePattern = Array(repeating: false, count: 16)
                    engine.tomPattern = Array(repeating: false, count: 16)
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.black)
                .cornerRadius(10)
                .accessibilityIdentifier("clearButton")
            }
        }
        .padding()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                engine.flushPersistedState()
            }
        }
    }

    // MARK: - UI helpers

    private func stepRow(title: String, pattern: Binding<[Bool]>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(width: 50, alignment: .leading)
            
            ForEach(0..<16, id: \.self) { index in
                // Safe access: ensure the index exists before reading or writing
                let isOn = pattern.wrappedValue.indices.contains(index) ? pattern.wrappedValue[index] : false

                Button {
                    if pattern.wrappedValue.indices.contains(index) {
                        pattern.wrappedValue[index].toggle()
                    }
                } label: {
                    let isBarBoundary = index % 4 == 0
                    let isPlayhead = engine.isPlaying && engine.currentStep == index

                    Rectangle()
                        .fill(
                            isOn
                            ? Color.blue
                            : (isBarBoundary ? Color.gray.opacity(0.45) : Color.gray.opacity(0.25))
                        )
                        .frame(width: 18, height: 28)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.yellow, lineWidth: isPlayhead ? 2 : 0)
                        )
                        .accessibilityIdentifier("\(title.lowercased())_step_\(index)")

                }
            }
        }
    }

    private func soundPickerRow(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .frame(width: 50, alignment: .leading)

            Picker(title, selection: selection) {
                Text("kick1").tag("kick1")
                Text("snare1").tag("snare1")
                Text("tom1").tag("tom1")
                Text("click").tag("click")  // you can use click as a sound for any track
            }
            .pickerStyle(.segmented)
        }
    }
}
