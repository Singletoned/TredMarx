//
//  TredMarxApp.swift
//  TredMarx
//
//  Created by Ed Singleton on 08/05/2025.
//

import SwiftUI

@main
struct TredMarxApp: App {
  @StateObject private var stepManager = StepCountManager()
  @StateObject private var healthManager = HealthKitManager()
  @State private var showingAuthError = false
  @State private var authError: Error?

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(stepManager)
        .environmentObject(healthManager)
        .task {
          do {
            try await healthManager.requestAuthorization()
            await healthManager.fetchUserMetrics()
            // Check if permission was denied after request
            if let error = healthManager.authorizationError {
              authError = error
              showingAuthError = true
            }
          } catch {
            authError = error
            showingAuthError = true
          }
        }
        .alert("Health Access Required", isPresented: $showingAuthError, presenting: authError) {
          _ in
          Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(url)
            }
          }
          Button("Cancel", role: .cancel) {}
        } message: { error in
          Text(error.localizedDescription)
        }
    }
  }
}
