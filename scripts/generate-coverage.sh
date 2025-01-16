#!/bin/bash

# Define variables
SCHEME="Supabase"               # Replace with your Xcode scheme name
OUTPUT_FILE="coverage.info"     # Output coverage file name
TEMP_COVERAGE_DIR="temp_coverage" # Temporary directory for intermediate coverage files

# Step 2: Find the profdata file
PROFDATA_DIR="$DERIVED_DATA_PATH/Build/ProfileData"
PROFDATA_FILE=$(find "$PROFDATA_DIR" -name "*.profdata" | head -n 1)

if [ -z "$PROFDATA_FILE" ]; then
  echo "No profdata file found. Exiting."
  exit 1
fi

echo "Found profdata file: $PROFDATA_FILE"

# Step 3: Get all test bundles
echo "Searching for test bundles in Debug-iphonesimulator..."
TEST_BUNDLES=$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" -type d -name "*.xctest")

if [ -z "$TEST_BUNDLES" ]; then
  echo "No test bundles found. Ensure the tests are built successfully."
  exit 1
fi

echo "Found test bundles:"
echo "$TEST_BUNDLES"

# Step 4: Export coverage data for each test bundle
mkdir -p "$TEMP_COVERAGE_DIR"
for TEST_BUNDLE in $TEST_BUNDLES; do
  BINARY_NAME=$(basename "$TEST_BUNDLE" .xctest)
  BINARY_PATH="$TEST_BUNDLE/$BINARY_NAME"

  if [ ! -f "$BINARY_PATH" ]; then
    echo "No binary found in $TEST_BUNDLE. Skipping..."
    continue
  fi

  echo "Exporting coverage data for binary: $BINARY_PATH"
  xcrun llvm-cov export \
    -format=lcov \
    -instr-profile "$PROFDATA_FILE" \
    -ignore-filename-regex "Tests/|.build|DerivedData|.derivedData" \
    "$BINARY_PATH" > "$TEMP_COVERAGE_DIR/$BINARY_NAME.info"

  if [ $? -ne 0 ]; then
    echo "Failed to export coverage for $BINARY_NAME. Skipping..."
    continue
  fi
done

# Step 5: Merge coverage data into a single file
echo "Merging coverage data..."
rm -f "$OUTPUT_FILE" # Ensure the output file doesn't already exist
for INFO_FILE in "$TEMP_COVERAGE_DIR"/*.info; do
  if [ -f "$INFO_FILE" ]; then
    lcov --add-tracefile "$INFO_FILE" --output-file "$OUTPUT_FILE"
    if [ $? -ne 0 ]; then
      echo "Failed to merge $INFO_FILE into $OUTPUT_FILE. Exiting."
      exit 1
    fi
  fi
done

echo "Coverage data exported to $OUTPUT_FILE"

# Step 6: Clean up
rm -rf "$TEMP_COVERAGE_DIR"
echo "Temporary files cleaned up."