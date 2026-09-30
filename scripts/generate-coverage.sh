#!/bin/bash

# Define variables
SCHEME="Supabase"               # Replace with your Xcode scheme name
OUTPUT_FILE="lcov.info"     # Output coverage file name
TEMP_COVERAGE_DIR="temp_coverage" # Temporary directory for intermediate coverage files

# Step 2: Find the profdata file
PROFDATA_DIR="$DERIVED_DATA_PATH/Build/ProfileData"
mkdir -p "$TEMP_COVERAGE_DIR"
PROFDATA_FILES=()
while IFS= read -r -d '' file; do
  PROFDATA_FILES+=("$file")
done < <(find "$PROFDATA_DIR" -name "*.profdata" -print0)

if [ "${#PROFDATA_FILES[@]}" -eq 0 ]; then
  echo "No profdata file found. Exiting."
  exit 1
elif [ "${#PROFDATA_FILES[@]}" -eq 1 ]; then
  PROFDATA_FILE="${PROFDATA_FILES[0]}"
  echo "Found profdata file: $PROFDATA_FILE"
else
  # More than one .profdata under DerivedData (e.g. a leftover from a
  # restored cache) — merge them instead of picking one arbitrarily.
  PROFDATA_FILE="$TEMP_COVERAGE_DIR/merged.profdata"
  echo "Found ${#PROFDATA_FILES[@]} profdata files; merging into $PROFDATA_FILE:"
  printf '  %s\n' "${PROFDATA_FILES[@]}"
  xcrun llvm-profdata merge -o "$PROFDATA_FILE" "${PROFDATA_FILES[@]}"
fi

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
for TEST_BUNDLE in $TEST_BUNDLES; do
  BINARY_NAME=$(basename "$TEST_BUNDLE" .xctest)
  BINARY_PATH="$TEST_BUNDLE/$BINARY_NAME"

  if [ ! -f "$BINARY_PATH" ]; then
    echo "No binary found in $TEST_BUNDLE. Skipping..."
    continue
  fi

  echo "Exporting coverage data for binary: $BINARY_PATH"
  EXPORT_STDERR="$TEMP_COVERAGE_DIR/$BINARY_NAME.stderr"
  xcrun llvm-cov export \
    -format=lcov \
    -instr-profile "$PROFDATA_FILE" \
    -ignore-filename-regex "Tests/|.build|DerivedData|.derivedData|Deprecated/|Deprecated.swift" \
    "$BINARY_PATH" > "$TEMP_COVERAGE_DIR/$BINARY_NAME.info" 2> "$EXPORT_STDERR"
  EXPORT_STATUS=$?
  cat "$EXPORT_STDERR" >&2

  if [ $EXPORT_STATUS -ne 0 ]; then
    echo "Failed to export coverage for $BINARY_NAME. Skipping..."
    continue
  fi

  if grep -q "profile data may be out of date" "$EXPORT_STDERR"; then
    echo "error: $PROFDATA_FILE is stale relative to $BINARY_NAME (llvm-cov reported profile data may be out of date)." >&2
    echo "Refusing to publish coverage computed against stale profiling data. Re-run the job or clear the DerivedData cache." >&2
    exit 1
  fi
done

# Step 5: Merge coverage data into a single file
echo "Merging coverage data..."
rm -f "$OUTPUT_FILE" # Ensure the output file doesn't already exist

for INFO_FILE in "$TEMP_COVERAGE_DIR"/*.info; do
  if [ -f "$INFO_FILE" ]; then
    lcov \
      --ignore-errors inconsistent \
      --add-tracefile "$INFO_FILE" \
      --output-file "$OUTPUT_FILE"
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