import Foundation
import HealthKit

@MainActor class HealthKitManager: ObservableObject {
  let healthStore = HKHealthStore()
  @Published var userHeight: Double?
  @Published var userWeight: Double?
  @Published var authorizationError: HealthError?
  @Published var isAuthorized = false

  func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw HealthError.notAvailable
    }

    let typesToShare: Set = [
      HKQuantityType.workoutType(),
      HKQuantityType(.stepCount),
      HKQuantityType(.distanceWalkingRunning),
      HKQuantityType(.activeEnergyBurned),
    ]

    let typesToRead: Set = [
      HKQuantityType(.stepCount),
      HKQuantityType(.height),
      HKQuantityType(.bodyMass),
    ]

    try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)

    // Check if we actually got write permission for workouts (the minimum required)
    let workoutStatus = healthStore.authorizationStatus(for: HKQuantityType.workoutType())
    if workoutStatus == .sharingDenied {
      authorizationError = .permissionDenied
      isAuthorized = false
    } else {
      authorizationError = nil
      isAuthorized = true
    }
  }

  func fetchUserMetrics() async {
    let heightType = HKQuantityType(.height)
    let weightType = HKQuantityType(.bodyMass)

    let heightQuery = HKSampleQuery(
      sampleType: heightType,
      predicate: nil,
      limit: 1,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
    ) { [weak self] _, samples, _ in
      guard let strongSelf = self else { return }
      if let heightSample = samples?.first as? HKQuantitySample {
        let heightInMeters = heightSample.quantity.doubleValue(for: .meter())
        DispatchQueue.main.async {
          strongSelf.userHeight = heightInMeters
        }
      }
    }

    let weightQuery = HKSampleQuery(
      sampleType: weightType,
      predicate: nil,
      limit: 1,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
    ) { [weak self] _, samples, _ in
      guard let strongSelf = self else { return }
      if let weightSample = samples?.first as? HKQuantitySample {
        let weightInKg = weightSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        DispatchQueue.main.async {
          strongSelf.userWeight = weightInKg
        }
      }
    }

    self.healthStore.execute(heightQuery)
    self.healthStore.execute(weightQuery)
  }

  func saveWorkout(steps: Int, duration: TimeInterval, distanceKm: Double, startDate: Date)
    async throws
  {
    // Calculate calories using MET formula
    // MET value for walking varies by speed, using moderate pace (3-4 mph) ≈ 3.5 METs
    let met = 3.5
    let weightKg = userWeight ?? 70.0  // Default to 70kg if weight not available
    let durationHours = duration / 3600.0

    // Calories = MET × Weight (kg) × Duration (hours)
    let caloriesBurned = met * weightKg * durationHours
    let energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: caloriesBurned)

    // Convert distance to meters for HealthKit
    let distance = HKQuantity(unit: .meter(), doubleValue: distanceKm * 1000)

    let endDate = Date()

    // Create step sample for the workout
    let stepsQuantity = HKQuantity(unit: .count(), doubleValue: Double(steps))
    let stepsType = HKQuantityType(.stepCount)
    let stepsSample = HKQuantitySample(
      type: stepsType,
      quantity: stepsQuantity,
      start: startDate,
      end: endDate,
      metadata: [HKMetadataKeyWasUserEntered: false]
    )

    // Create the workout
    if #available(iOS 17.0, *) {
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = .walking
      configuration.locationType = .indoor

      let builder = HKWorkoutBuilder(
        healthStore: healthStore, configuration: configuration, device: nil)
      try await builder.beginCollection(at: startDate)

      // Add step sample to the workout
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        builder.add([stepsSample]) { success, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }

      let distanceSample = HKQuantitySample(
        type: HKQuantityType(.distanceWalkingRunning),
        quantity: distance,
        start: startDate,
        end: endDate
      )
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        builder.add([distanceSample]) { success, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }

      let energySample = HKQuantitySample(
        type: HKQuantityType(.activeEnergyBurned),
        quantity: energyBurned,
        start: startDate,
        end: endDate
      )
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        builder.add([energySample]) { success, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        builder.endCollection(withEnd: endDate) { success, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
      _ = try await builder.finishWorkout()
    } else {
      let workout = HKWorkout(
        activityType: .walking,
        start: startDate,
        end: endDate,
        duration: duration,
        totalEnergyBurned: energyBurned,
        totalDistance: distance,
        metadata: [HKMetadataKeyIndoorWorkout: true]
      )

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        healthStore.save(workout) { success, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    }
  }
}

enum HealthError: LocalizedError {
  case notAvailable
  case permissionDenied

  var errorDescription: String? {
    switch self {
    case .notAvailable:
      return "Health data is not available on this device"
    case .permissionDenied:
      return
        "Health access was denied. Please enable it in Settings > Privacy > Health > TredMarx"
    }
  }
}
