//
//  TredMarxTests.swift
//  TredMarxTests
//
//  Created by Ed Singleton on 08/05/2025.
//

import CoreMotion
import HealthKit
import XCTest

@testable import TredMarx

// MARK: - Mocks for CMPedometer (existing)
class MockPedometer: CMPedometer {
  var mockSteps: Int = 0
  var mockHandler: ((CMPedometerData?, Error?) -> Void)?

  override func startUpdates(from start: Date, withHandler handler: @escaping CMPedometerHandler) {
    mockHandler = handler
    // Simulate step updates
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      let data = MockPedometerData(numberOfSteps: self.mockSteps)
      handler(data, nil)
    }
  }

  override class func isStepCountingAvailable() -> Bool {
    return true
  }
}

class MockPedometerData: CMPedometerData {
  private let steps: NSNumber

  init(numberOfSteps: Int) {
    self.steps = NSNumber(value: numberOfSteps)
    super.init()
  }

  required init?(coder: NSCoder) {
    self.steps = NSNumber(value: 0)
    super.init(coder: coder)
  }

  override var numberOfSteps: NSNumber {
    return steps
  }
}

// MARK: - Mock HealthKitManager
@MainActor  // HealthKitManager is @MainActor, so subclass should be too.
class MockHealthKitManager: HealthKitManager {
  var saveWorkoutCalled = false
  var lastSavedWorkoutData:
    (steps: Int, duration: TimeInterval, distanceKm: Double, startDate: Date)?
  var saveWorkoutShouldThrowError: Error?  // For testing error handling if needed

  // Override to prevent actual HealthKit interaction and record call details
  override func saveWorkout(steps: Int, duration: TimeInterval, distanceKm: Double, startDate: Date)
    async throws
  {
    if let error = saveWorkoutShouldThrowError {
      self.saveWorkoutCalled = true  // Record call even if it throws
      self.lastSavedWorkoutData = (steps, duration, distanceKm, startDate)
      throw error
    }
    saveWorkoutCalled = true
    lastSavedWorkoutData = (steps, duration, distanceKm, startDate)
    // Importantly, we do NOT call super.saveWorkout()
  }

  // Override requestAuthorization to prevent actual HealthKit calls and simulate success.
  override func requestAuthorization() async throws {
    // Do nothing, or simulate success. Do not call super.requestAuthorization().
    print("MockHealthKitManager: Skipped actual HealthKit authorization request.")
  }

  // Optionally, override other methods like fetchUserMetrics if needed for specific tests
  // to prevent them from hitting the real HealthKit store.
  override func fetchUserMetrics() async {
    // Simulate fetching metrics or set mock values if your tests depend on them.
    print("MockHealthKitManager: Skipped actual fetchUserMetrics.")
    // self.userHeight = 1.75 // example mock value
    // self.userWeight = 70.0 // example mock value
  }
}

// MARK: - TredMarxTests
final class TredMarxTests: XCTestCase {
  var stepManager: StepCountManager!
  var healthManager: MockHealthKitManager!  // Use the mock type
  var mockPedometer: MockPedometer!

  override func setUp() async throws {
    try await super.setUp()
    mockPedometer = MockPedometer()
    stepManager = StepCountManager(pedometer: mockPedometer)
    healthManager = await MockHealthKitManager()  // Instantiate the mock, now with await
    // This will now call the overridden requestAuthorization in MockHealthKitManager
    try await healthManager.requestAuthorization()
  }

  override func tearDown() {
    stepManager = nil
    super.tearDown()
  }

  func testStepCountInitialization() {
    XCTAssertEqual(stepManager.steps, 0, "Step count should initialize to 0")
    XCTAssertFalse(stepManager.isTracking, "Should not be tracking initially")
  }

  func testStartTracking() async throws {
    // Only run if step counting is available on the device
    guard CMPedometer.isStepCountingAvailable() else {
      throw XCTSkip("Step counting not available on this device")
    }

    stepManager.startTracking()

    XCTAssertTrue(stepManager.isTracking, "Should be tracking after start")
    XCTAssertNotNil(stepManager.startDate, "Start date should be set")
  }

  func testStopTracking() async throws {
    stepManager.startTracking()
    stepManager.stopTracking()

    XCTAssertFalse(stepManager.isTracking, "Should not be tracking after stop")
    XCTAssertNil(stepManager.startDate, "Start date should be cleared")
    XCTAssertEqual(stepManager.steps, 0, "Steps should reset to 0")
  }

  @MainActor  // Ensure this test runs on the Main Actor
  func testWorkoutSession() async throws {
    // Set up mock step count
    mockPedometer.mockSteps = 1000

    // Start tracking
    stepManager.startTracking()

    // Wait for mock pedometer to update steps
    try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    // Verify steps were counted.
    // The mock pedometer updates asynchronously, so we need to wait for the update.
    let stepExpectation = XCTestExpectation(description: "Wait for step count to update to 1000")

    // Poll for the step count update, or use a more sophisticated publisher expectation if available.
    // This simple polling checks a few times.
    var attempts = 0
    func checkSteps() {
      attempts += 1
      if stepManager.steps == 1000 {
        stepExpectation.fulfill()
      } else if attempts < 10 {  // Try up to 10 times (1 second total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          checkSteps()
        }
      } else {
        // If still not 1000, the expectation will time out, failing the test.
        // Or, you could explicitly fail here:
        // XCTFail("Step count did not update to 1000. Was: \(stepManager.steps)")
        // stepExpectation.fulfill() // Fulfill to prevent timeout if XCTFail is used.
      }
    }
    checkSteps()

    await fulfillment(of: [stepExpectation], timeout: 1.5)  // Increased timeout slightly
    XCTAssertEqual(
      stepManager.steps, 1000, "Should have recorded 1000 steps. Actual: \(stepManager.steps)")

    // Capture session data *before* stopping tracking, as stopTracking resets these values.
    let capturedSteps = stepManager.steps
    let capturedDuration = stepManager.sessionDuration
    guard let capturedStartDate = stepManager.startDate else {
      XCTFail("startDate should be valid before stopping tracking.")
      return  // Exit if startDate is nil, as it's crucial for the test.
    }

    XCTAssertGreaterThan(
      capturedDuration, 0, "Session duration should be greater than 0 before stop.")

    stepManager.stopTracking()

    // Attempt to save workout using the mock manager and captured data
    let testDistanceKm = 1.0
    try await healthManager.saveWorkout(
      steps: capturedSteps,
      duration: capturedDuration,
      distanceKm: testDistanceKm,
      startDate: capturedStartDate  // Use the actual start date from the session
    )

    // Verify that the mock's saveWorkout was called and with the correct data
    XCTAssertTrue(
      healthManager.saveWorkoutCalled, "MockHealthKitManager's saveWorkout should have been called."
    )
    if let savedData = healthManager.lastSavedWorkoutData {
      XCTAssertEqual(
        savedData.steps, capturedSteps,
        "Mock captured correct steps. Expected \(capturedSteps), got \(savedData.steps)")
      XCTAssertEqual(
        savedData.duration, capturedDuration,
        "Mock captured correct duration. Expected \(capturedDuration), got \(savedData.duration)")
      XCTAssertEqual(
        savedData.distanceKm, testDistanceKm,
        "Mock captured correct distance. Expected \(testDistanceKm), got \(savedData.distanceKm)")
      XCTAssertEqual(
        savedData.startDate, capturedStartDate,
        "Mock captured correct start date. Expected \(capturedStartDate), got \(savedData.startDate)"
      )
    } else {
      XCTFail("lastSavedWorkoutData was not set on the mock HealthKitManager.")
    }
  }
}
