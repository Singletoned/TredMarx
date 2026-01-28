import Combine
import CoreMotion
import Foundation
import UIKit

class StepCountManager: ObservableObject {
  private let pedometer: CMPedometer

  init(pedometer: CMPedometer = CMPedometer()) {
    self.pedometer = pedometer
    setupNotifications()
  }
  private let defaults = UserDefaults.standard
  private static let startTimeKey = "sessionStartTime"
  @Published var steps: Int = 0
  @Published var isTracking = false
  @Published private(set) var startDate: Date?
  @Published var pedometerError: Error?

  private func setupNotifications() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleBackgroundTransition),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleForegroundTransition),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }

  @objc private func handleBackgroundTransition() {
    // Ensure start time is saved when entering background
    if isTracking {
      defaults.set(startDate, forKey: Self.startTimeKey)
    }
  }

  @objc private func handleForegroundTransition() {
    // Restore tracking state if needed
    if isTracking {
      if let savedDate = defaults.object(forKey: Self.startTimeKey) as? Date {
        startDate = savedDate
      }
    }
  }

  var sessionDuration: TimeInterval {
    guard let start = startDate else { return 0 }
    return Date().timeIntervalSince(start)
  }

  func startTracking() {
    guard type(of: pedometer).isStepCountingAvailable() else {
      pedometerError = StepCountError.notAvailable
      return
    }

    let now = Date()
    startDate = now
    defaults.set(now, forKey: Self.startTimeKey)
    isTracking = true
    steps = 0
    pedometerError = nil

    pedometer.startUpdates(from: Date()) { [weak self] data, error in
      DispatchQueue.main.async {
        if let error = error {
          self?.pedometerError = error
          self?.stopTracking()
          return
        }

        guard let data = data else { return }
        self?.steps = Int(truncating: data.numberOfSteps)
      }
    }
  }

  func stopTracking() {
    pedometer.stopUpdates()
    isTracking = false
    startDate = nil
    defaults.removeObject(forKey: Self.startTimeKey)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

enum StepCountError: LocalizedError {
  case notAvailable

  var errorDescription: String? {
    switch self {
    case .notAvailable:
      return "Step counting is not available on this device"
    }
  }
}
