# Default recipe to show available commands
default:
    @just --list

# Format code
format *files:
    swift-format format . --recursive --in-place

# Run tests
test:
    xcodebuild test \
      -scheme TredMarx \
      -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
      -resultBundlePath ./TestResults.xcresult
    xcrun xcresulttool get object --legacy --path ./TestResults.xcresult --format json

# Run tests with minimal output
test-quiet:
    xcodebuild test \
      -scheme TredMarx \
      -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
      -resultBundlePath ./TestResults.xcresult \
      -quiet 2>&1 | grep -E "(error:|warning:|failed|passed|Test Suite)"

# Run tests with pretty output (requires xcpretty)
test-pretty:
    xcodebuild test \
      -scheme TredMarx \
      -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
      -resultBundlePath ./TestResults.xcresult \
      | xcpretty --test

compile:
    xcodebuild build -scheme TredMarx -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' | xcpretty --report json-compilation-database
