#!/bin/bash

SCHEME="Supabase"
OUTPUT_FILE="lcov.info"
TEMP_COVERAGE_DIR="temp_coverage"

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
  # The DerivedData cache can restore profiles from earlier runs, even from another branch. Only
  # the newest belongs to this run: merging the others would count lines these tests never ran,
  # and a freshly merged file would also hide them from the staleness check below.
  PROFDATA_FILE=$(ls -t "${PROFDATA_FILES[@]}" | head -n 1)
  echo "Found ${#PROFDATA_FILES[@]} profdata files; using the newest: $PROFDATA_FILE"
  printf '  %s\n' "${PROFDATA_FILES[@]}"
fi

echo "Searching for test bundles in Debug-iphonesimulator..."
TEST_BUNDLES=$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" -type d -name "*.xctest")

if [ -z "$TEST_BUNDLES" ]; then
  echo "No test bundles found. Ensure the tests are built successfully."
  exit 1
fi

echo "Found test bundles:"
echo "$TEST_BUNDLES"

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

echo "Merging coverage data..."
rm -f "$OUTPUT_FILE"

# One lcov call for every tracefile: each call writes `--output-file` from scratch.
TRACEFILE_ARGS=()
for INFO_FILE in "$TEMP_COVERAGE_DIR"/*.info; do
  if [ -f "$INFO_FILE" ]; then
    TRACEFILE_ARGS+=(--add-tracefile "$INFO_FILE")
  fi
done

if [ "${#TRACEFILE_ARGS[@]}" -eq 0 ]; then
  echo "No coverage data was exported. Exiting."
  exit 1
fi

if ! lcov --ignore-errors inconsistent "${TRACEFILE_ARGS[@]}" --output-file "$OUTPUT_FILE"; then
  echo "Failed to merge coverage data into $OUTPUT_FILE. Exiting."
  exit 1
fi

echo "Coverage data exported to $OUTPUT_FILE"

rm -rf "$TEMP_COVERAGE_DIR"
echo "Temporary files cleaned up."