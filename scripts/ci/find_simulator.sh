#!/bin/bash
# find_simulator.sh - Reusable script for simulator discovery in GitHub Actions CI
# Usage: ./find_simulator.sh <PLATFORM_KEY> <DEVICE_MATCH> <FALLBACK_DEVICE> <OUTPUT_PREFIX>

set -euo pipefail

# Validate arguments
if [ $# -ne 4 ]; then
    echo "ERROR: Invalid number of arguments"
    echo "Usage: $0 <PLATFORM_KEY> <DEVICE_MATCH> <FALLBACK_DEVICE> <OUTPUT_PREFIX>"
    echo "Example: $0 'iOS' 'iPhone' 'iPhone 14' 'ios'"
    exit 1
fi

PLATFORM_KEY="$1"
DEVICE_MATCH="$2"
FALLBACK_DEVICE="$3"
OUTPUT_PREFIX="$4"

# Reusable function for simulator discovery
find_simulator() {
    local PLATFORM_KEY="$1"
    local DEVICE_MATCH="$2"
    local FALLBACK_DEVICE="$3"
    local OUTPUT_PREFIX="$4"

    echo "=== ${PLATFORM_KEY} Simulator Discovery ==="

    # Find an available simulator and capture both name and UDID
    echo "Querying available ${PLATFORM_KEY} simulators..."
    if ! JSON_OUTPUT=$(xcrun simctl list --json devices available 2>/dev/null); then
        # Capture exit code and stderr immediately after the failing command
        EXIT_CODE=$?
        STDERR_OUTPUT=$(xcrun simctl list --json devices available 2>&1 >/dev/null)
        echo "ERROR: xcrun simctl list failed with exit code $EXIT_CODE"
        echo "xcrun stderr output: $STDERR_OUTPUT"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit $EXIT_CODE
    fi

    # Validate JSON output is non-empty
    if [ -z "$JSON_OUTPUT" ]; then
        echo "ERROR: xcrun simctl list returned empty output"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is not installed, attempting to install it..."

        # Attempt to install jq based on the OS
        if command -v brew >/dev/null 2>&1; then
            echo "Detected macOS/Homebrew, installing jq with brew..."
            if brew update && brew install jq; then
                echo "Successfully installed jq via brew"
            else
                echo "Failed to install jq via brew"
                echo "jq is required for parsing simulator device information"
                echo ""
                echo "To install jq manually on macOS:"
                echo "  brew update && brew install jq"
                echo ""
                echo "Or add jq to your GitHub Actions runner image"
                echo ""
                echo "Available devices list:"
                xcrun simctl list devices available || true
                exit 1
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            echo "Detected Linux/apt-get, installing jq with apt-get..."
            if apt-get update && apt-get install -y jq; then
                echo "Successfully installed jq via apt-get"
            else
                echo "Failed to install jq via apt-get"
                echo "jq is required for parsing simulator device information"
                echo ""
                echo "To install jq manually on Linux:"
                echo "  apt-get update && apt-get install -y jq"
                echo ""
                echo "Or add jq to your GitHub Actions runner image"
                echo ""
                echo "Available devices list:"
                xcrun simctl list devices available || true
                exit 1
            fi
        elif command -v choco >/dev/null 2>&1; then
            echo "Detected Windows/Chocolatey, installing jq with choco..."
            if choco install jq -y; then
                echo "Successfully installed jq via choco"
            else
                echo "Failed to install jq via choco"
                echo "jq is required for parsing simulator device information"
                echo ""
                echo "To install jq manually on Windows:"
                echo "  choco install jq -y"
                echo ""
                echo "Or add jq to your GitHub Actions runner image"
                echo ""
                echo "Available devices list:"
                xcrun simctl list devices available || true
                exit 1
            fi
        else
            echo "Unable to detect package manager (brew, apt-get, or choco)"
            echo "jq is required for parsing simulator device information"
            echo ""
            echo "To install jq on macOS:"
            echo "  brew update && brew install jq"
            echo ""
            echo "To install jq on Linux:"
            echo "  apt-get update && apt-get install -y jq"
            echo ""
            echo "To install jq on Windows:"
            echo "  choco install jq -y"
            echo ""
            echo "Or add jq to your GitHub Actions runner image"
            echo ""
            echo "Available devices list:"
            xcrun simctl list devices available || true
            exit 1
        fi
    fi

    echo "Parsing JSON output with jq..."
    if ! SIMULATOR_LINE=$(echo "$JSON_OUTPUT" | jq -r "
        .devices
        | to_entries[]
        | select(.key | contains(\"$PLATFORM_KEY\"))
        | .value[]
        | select(.name | contains(\"$DEVICE_MATCH\"))
        | select(.isAvailable == true)
        | select(.state == \"Shutdown\" or .state == \"Booted\")
        | [.name, .udid] | @tsv" | head -1 2>/dev/null); then
        # Capture exit code and stderr immediately after the failing command
        EXIT_CODE=$?
        STDERR_OUTPUT=$(echo "$JSON_OUTPUT" | jq -r "
            .devices
            | to_entries[]
            | select(.key | contains(\"$PLATFORM_KEY\"))
            | .value[]
            | select(.name | contains(\"$DEVICE_MATCH\"))
            | select(.isAvailable == true)
            | select(.state == \"Shutdown\" or .state == \"Booted\")
            | [.name, .udid] | @tsv" | head -1 2>&1 >/dev/null)
        echo "ERROR: jq parsing failed with exit code $EXIT_CODE"
        echo "jq stderr output: $STDERR_OUTPUT"
        echo "JSON output was:"
        echo "$JSON_OUTPUT"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit $EXIT_CODE
    fi

    if [ -n "${SIMULATOR_LINE:-}" ]; then
        SIMULATOR_NAME="$(echo "$SIMULATOR_LINE" | cut -f1)"
        SIMULATOR_UDID="$(echo "$SIMULATOR_LINE" | cut -f2)"
        echo "Found available ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
    else
        echo "No available ${PLATFORM_KEY} simulators found, attempting fallback to '$FALLBACK_DEVICE'..."

        # Verify fallback device exists
        if ! xcrun simctl list devices available | grep -q "$FALLBACK_DEVICE"; then
            echo "ERROR: Fallback device '$FALLBACK_DEVICE' not found in available simulators"
            echo "Full list of available devices:"
            xcrun simctl list devices available
            echo ""
            echo "JSON devices list:"
            echo "$JSON_OUTPUT" | jq '.devices' 2>/dev/null || echo "JSON parsing failed"
            exit 1
        fi

        SIMULATOR_NAME="$FALLBACK_DEVICE"
        SIMULATOR_UDID=""
        echo "Using fallback ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME'"
    fi

    if [ -n "$SIMULATOR_UDID" ]; then
        echo "Ensuring simulator is booted: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        if ! xcrun simctl bootstatus "$SIMULATOR_UDID" -b 2>&1; then
            echo "Simulator not booted; attempting boot..."
            if ! xcrun simctl boot "$SIMULATOR_UDID" 2>&1; then
                echo "ERROR: Failed to boot simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
            echo "Waiting for simulator to be ready..."
            if ! xcrun simctl bootstatus "$SIMULATOR_UDID" -b 2>&1; then
                echo "ERROR: Failed to reach booted state for '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
        fi
    else
        echo "No UDID available, skipping boot (will use platform=name format)"
    fi

    echo "${OUTPUT_PREFIX}_simulator_name=$SIMULATOR_NAME" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_PREFIX}_simulator_udid=$SIMULATOR_UDID" >> "$GITHUB_OUTPUT"
    echo "Successfully configured ${PLATFORM_KEY} Simulator: name='$SIMULATOR_NAME' udid='${SIMULATOR_UDID:-N/A}'"
}

# Call the function with the provided arguments
find_simulator "$PLATFORM_KEY" "$DEVICE_MATCH" "$FALLBACK_DEVICE" "$OUTPUT_PREFIX"