//
//  ContentView.swift
//  TredMarx
//
//  Created by Ed Singleton on 08/05/2025.
//

import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var stepManager: StepCountManager
  @EnvironmentObject private var healthManager: HealthKitManager
  @State private var showingSaveAlert = false
  @State private var saveError: Error?
  @State private var distance: Double = 0.0
  @State private var selectedUnit: DistanceUnit = .kilometers
  @State private var showingDistancePrompt = false
  @State private var showingShortSessionAlert = false
  @State private var timerDisplay = "00:00"
  @State private var sessionStartDate: Date?
  @State private var sessionSteps: Int = 0
  @State private var sessionDuration: TimeInterval = 0
  @State private var isSaving = false
  @State private var showingPedometerError = false
  let timer = Timer.publish(every: 1.0, on: .main, in: .default).autoconnect()

  enum DistanceUnit: String, CaseIterable {
    case kilometers = "km"
    case miles = "mi"

    var label: String {
      switch self {
      case .kilometers: return "Kilometers"
      case .miles: return "Miles"
      }
    }
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("\(stepManager.steps)")
        .font(.system(size: 64, weight: .bold))
        .foregroundStyle(.tint)
        .accessibilityLabel("Step count")
        .accessibilityValue("\(stepManager.steps) steps")

      Text("Steps")
        .font(.title2)
        .accessibilityHidden(true)

      if stepManager.isTracking {
        Text(timerDisplay)
          .font(.title3)
          .monospacedDigit()
          .accessibilityLabel("Elapsed time")
          .accessibilityValue(timerDisplay)
          .onReceive(timer) { _ in
            if stepManager.isTracking {
              timerDisplay = formatElapsedTime(since: stepManager.startDate)
            }
          }
      }

      Button(action: toggleTracking) {
        Text(stepManager.isTracking ? "Stop Session" : "Start Session")
          .font(.title2)
          .padding()
          .background(stepManager.isTracking ? Color.red : Color.green)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .accessibilityLabel(
        stepManager.isTracking ? "Stop tracking session" : "Start tracking session"
      )
      .accessibilityHint(
        stepManager.isTracking ? "Ends the current workout" : "Begins counting your steps")
    }
    .padding()
    .sheet(isPresented: $showingDistancePrompt) {
      NavigationView {
        Form {
          Section {
            HStack {
              Label("Steps", systemImage: "figure.walk")
              Spacer()
              Text("\(sessionSteps)")
                .font(.headline)
            }
            HStack {
              Label("Duration", systemImage: "timer")
              Spacer()
              Text(formatDuration(sessionDuration))
                .font(.headline)
            }
          } header: {
            Text("Session Summary")
          }

          Section {
            HStack {
              TextField("Distance", value: $distance, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)

              Picker("Unit", selection: $selectedUnit) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                  Text(unit.rawValue).tag(unit)
                }
              }
              .pickerStyle(.segmented)
              .frame(width: 100)
            }
          } header: {
            Text("Distance Walked")
          } footer: {
            Text("Enter the distance shown on your treadmill")
              .font(.caption)
          }

          if healthManager.userWeight == nil {
            Section {
              Label(
                "Calorie calculation uses an estimated weight. Add your weight in Health for more accurate results.",
                systemImage: "info.circle"
              )
              .font(.footnote)
              .foregroundStyle(.secondary)
            }
          }
        }
        .navigationTitle("Save Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              showingDistancePrompt = false
              distance = 0.0
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              Task {
                isSaving = true
                do {
                  let distanceKm = selectedUnit == .kilometers ? distance : distance * 1.60934

                  try await healthManager.saveWorkout(
                    steps: sessionSteps,
                    duration: sessionDuration,
                    distanceKm: distanceKm,
                    startDate: sessionStartDate ?? Date(timeIntervalSinceNow: -sessionDuration)
                  )

                  showingDistancePrompt = false
                  distance = 0.0
                } catch {
                  saveError = error
                  showingSaveAlert = true
                }
                isSaving = false
              }
            } label: {
              if isSaving {
                ProgressView()
              } else {
                Text("Save")
              }
            }
            .font(.headline)
            .disabled(distance <= 0 || isSaving)
          }
        }
      }
    }
    .alert("Save Error", isPresented: $showingSaveAlert, presenting: saveError) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.localizedDescription)
    }
    .alert("Short Session", isPresented: $showingShortSessionAlert) {
      Button("Record Anyway") {
        showingDistancePrompt = true
      }
      Button("Discard", role: .cancel) {}
    } message: {
      Text("This session was less than a minute long. Do you want to record it?")
    }
    .alert(
      "Step Counting Error", isPresented: $showingPedometerError,
      presenting: stepManager.pedometerError
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.localizedDescription)
    }
    .onChange(of: stepManager.pedometerError != nil) { _, hasError in
      if hasError {
        showingPedometerError = true
      }
    }
  }

  private func formatElapsedTime(since startDate: Date?) -> String {
    guard let startDate = startDate else { return "00:00" }
    let elapsed = Int(Date().timeIntervalSince(startDate))
    let minutes = elapsed / 60
    let seconds = elapsed % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func toggleTracking() {
    if stepManager.isTracking {
      // Capture session data before stopping
      sessionSteps = stepManager.steps
      sessionDuration = stepManager.sessionDuration
      sessionStartDate = stepManager.startDate

      let duration = stepManager.sessionDuration
      stepManager.stopTracking()

      if duration < 60 {  // Less than a minute
        showingShortSessionAlert = true
      } else {
        showingDistancePrompt = true
      }
    } else {
      stepManager.startTracking()
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(StepCountManager())
    .environmentObject(HealthKitManager())
}
