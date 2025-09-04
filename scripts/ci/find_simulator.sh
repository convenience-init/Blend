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

# Timeout configuration
TIMEOUT_SEC=300  # 5 minutes timeout for simulator operations

# Timeout wrapper for bootstatus commands to prevent infinite hangs
timeout_bootstatus() {
    local simulator_name="$1"
    local simulator_udid="$2"
    local context_message="$3"
    
    echo "Starting bootstatus check with ${TIMEOUT_SEC}s timeout: $simulator_name ($simulator_udid)"
    
    # Start bootstatus in background
    xcrun simctl bootstatus "$simulator_udid" -b 2>&1 &
    local bootstatus_pid=$!
    
    # Start timeout sleeper in background
    (
        sleep "$TIMEOUT_SEC"
        if kill -0 "$bootstatus_pid" 2>/dev/null; then
            echo "TIMEOUT: bootstatus command timed out after ${TIMEOUT_SEC}s for $simulator_name ($simulator_udid)"
            kill "$bootstatus_pid" 2>/dev/null || true
        fi
    ) &
    local sleeper_pid=$!
    
    # Wait for bootstatus to finish
    local exit_code
    wait "$bootstatus_pid" 2>/dev/null
    exit_code=$?
    
    # Clean up sleeper process
    kill "$sleeper_pid" 2>/dev/null || true
    wait "$sleeper_pid" 2>/dev/null || true
    
    # Check if we timed out (process was killed)
    if ! kill -0 "$bootstatus_pid" 2>/dev/null && [ $exit_code -eq 143 ]; then
        # Process was killed (SIGTERM = 143), treat as timeout
        echo "ERROR: $context_message timed out after ${TIMEOUT_SEC}s for '$simulator_name' (UDID: $simulator_udid)"
        echo "Available devices from xcrun simctl:"
        xcrun simctl list devices available || true
        echo ""
        echo "Device details:"
        xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$simulator_name" || true
        return 1
    fi
    
    # Return the original exit code
    return $exit_code
}

# Reusable function for simulator discovery
find_simulator() {
    local PLATFORM_KEY="$1"
    local DEVICE_MATCH="$2"
    local FALLBACK_DEVICE="$3"
    local OUTPUT_PREFIX="$4"

    echo "=== ${PLATFORM_KEY} Simulator Discovery ==="

    # Preflight checks - fail fast on unsupported environments
    echo "Performing preflight checks..."

    # Check if running on macOS (Darwin)
    if ! uname -s | grep -q "Darwin"; then
        echo "ERROR: This script requires macOS (Darwin) to run iOS simulators" >&2
        echo "Current OS: $(uname -s)" >&2
        echo "iOS Simulator discovery is only supported on macOS with Xcode installed" >&2
        exit 1
    fi

    # Check if xcrun command exists and is executable
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "ERROR: xcrun command not found in PATH" >&2
        echo "xcrun is required for iOS simulator management and is part of Xcode" >&2
        echo "Please ensure Xcode is installed and xcrun is available in your PATH" >&2
        echo "You can verify Xcode installation with: xcode-select -p" >&2
        exit 1
    fi

    # Verify xcrun can execute (not just exists)
    if ! xcrun --version >/dev/null 2>&1; then
        echo "ERROR: xcrun command exists but is not executable" >&2
        echo "This may indicate a corrupted Xcode installation" >&2
        echo "Try running: xcode-select --install" >&2
        echo "Or reinstall Xcode Command Line Tools" >&2
        exit 1
    fi

    echo "✓ Preflight checks passed - macOS environment with xcrun detected"

    # Find an available simulator and capture both name and UDID
    echo "Querying available ${PLATFORM_KEY} simulators..."

    # Run xcrun command once and capture both output and exit code
    JSON_OUTPUT=$(xcrun simctl list --json devices available 2>&1)
    EXIT_CODE=$?

    # Check if command failed
    if [ $EXIT_CODE -ne 0 ]; then
        echo "ERROR: xcrun simctl list failed with exit code $EXIT_CODE"
        echo "xcrun output: $JSON_OUTPUT"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit $EXIT_CODE
    fi

    # Extract stderr from mixed output if needed (JSON_OUTPUT contains both stdout and stderr)
    # For successful execution, JSON_OUTPUT should contain valid JSON

    # Validate JSON output is non-empty
    if [ -z "$JSON_OUTPUT" ]; then
        echo "ERROR: xcrun simctl list returned empty output"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required but not found in PATH" >&2
        echo "jq is needed to parse simulator device information from xcrun output" >&2
        echo "" >&2
        echo "For CI/GitHub Actions, add jq to your runner image:" >&2
        echo "  - name: Install jq" >&2
        echo "    run: |" >&2
        echo "      if command -v brew >/dev/null 2>&1; then" >&2
        echo "        brew install jq" >&2
        echo "      elif command -v apt-get >/dev/null 2>&1; then" >&2
        echo "        sudo apt-get update && sudo apt-get install -y jq" >&2
        echo "      elif command -v choco >/dev/null 2>&1; then" >&2
        echo "        choco install jq -y" >&2
        echo "      fi" >&2
        echo "" >&2
        echo "For manual installation:" >&2
        echo "  macOS: brew install jq" >&2
        echo "  Linux: sudo apt-get install jq" >&2
        echo "  Windows: choco install jq" >&2
        echo "" >&2
        echo "Available devices list:" >&2
        xcrun simctl list devices available || true
        exit 1
    fi

    echo "Parsing JSON output with jq..."
    if ! SIMULATOR_LINE=$(echo "$JSON_OUTPUT" | jq --arg platform_key "$PLATFORM_KEY" --arg device_match "$DEVICE_MATCH" -r "
        .devices
        | to_entries[]
        | select(.key | contains(\$platform_key))
        | .value[]
        | select(.name | contains(\$device_match))
        | select(.isAvailable == true)
        | select(.state == \"Shutdown\" or .state == \"Booted\")
        | [.name, .udid] | @tsv" 2>/dev/null | head -1); then
        # Capture exit code and stderr immediately after the failing command
        EXIT_CODE=$?
        STDERR_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg platform_key "$PLATFORM_KEY" --arg device_match "$DEVICE_MATCH" -r "
            .devices
            | to_entries[]
            | select(.key | contains(\$platform_key))
            | .value[]
            | select(.name | contains(\$device_match))
            | select(.isAvailable == true)
            | select(.state == \"Shutdown\" or .state == \"Booted\")
            | [.name, .udid] | @tsv" 2>&1 | head -1 >/dev/null)
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

        # Resolve fallback UDID from JSON first
        SIMULATOR_UDID="$(
            jq -r --arg platform "$PLATFORM_KEY" --arg device "$FALLBACK_DEVICE" '
                .devices
                | to_entries[]
                | select(.key | contains($platform))
                | .value[]
                | select(.name == $device and .isAvailable == true)
                | .udid
            ' <<<"$JSON_OUTPUT" | head -n 1
        )"

        # If JSON resolution failed, try parsing xcrun simctl list output
        if [ -z "$SIMULATOR_UDID" ] || [ "$SIMULATOR_UDID" = "null" ]; then
            echo "JSON UDID resolution failed, trying xcrun simctl list parsing..."
            SIMULATOR_UDID="$(
                xcrun simctl list devices available | \
                grep "$FALLBACK_DEVICE" | \
                sed -n 's/.*(\([^)]*\)).*/\1/p' | \
                head -n 1
            )"
        fi

        # Final check - exit if we still don't have a UDID
        if [ -z "$SIMULATOR_UDID" ] || [ "$SIMULATOR_UDID" = "null" ]; then
            echo "ERROR: Could not resolve UDID for fallback device '$FALLBACK_DEVICE'"
            echo "Available devices from JSON:"
            echo "$JSON_OUTPUT" | jq '.devices' 2>/dev/null || echo "JSON parsing failed"
            echo ""
            echo "Available devices from xcrun simctl:"
            xcrun simctl list devices available || true
            exit 1
        fi
        SIMULATOR_NAME="$FALLBACK_DEVICE"
        echo "Using fallback ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"

        # Ensure fallback device is booted for stable UDID
        echo "Ensuring fallback simulator is booted: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Fallback simulator bootstatus check"; then
            echo "Fallback simulator not booted; attempting boot..."
            if ! xcrun simctl boot "$SIMULATOR_UDID" 2>&1; then
                echo "ERROR: Failed to boot fallback simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
            echo "Waiting for fallback simulator to be ready..."
            if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Fallback simulator readiness check"; then
                echo "ERROR: Failed to reach booted state for fallback simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
            echo "Fallback simulator successfully booted"
        else
            echo "Fallback simulator already booted"
        fi
    fi

    # Note: Fallback device is already booted above, so we only need to handle the primary device here
    if [ -n "$SIMULATOR_UDID" ] && [ "$SIMULATOR_NAME" != "$FALLBACK_DEVICE" ]; then
        echo "Ensuring simulator is booted: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Primary simulator bootstatus check"; then
            echo "Simulator not booted; attempting boot..."
            if ! xcrun simctl boot "$SIMULATOR_UDID" 2>&1; then
                echo "ERROR: Failed to boot simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
            echo "Waiting for simulator to be ready..."
            if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Primary simulator readiness check"; then
                echo "ERROR: Failed to reach booted state for '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -A 2 -B 2 "$SIMULATOR_NAME" || true
                exit 1
            fi
        fi
    fi

    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        # Validate that we have non-empty simulator information before writing outputs
        if [ -z "$SIMULATOR_NAME" ]; then
            echo "ERROR: Simulator name is empty or null - cannot proceed with CI"
            exit 1
        fi
        if [ -z "$SIMULATOR_UDID" ]; then
            echo "ERROR: Simulator UDID is empty or null - cannot proceed with CI"
            exit 1
        fi
        
        {
            printf '%s\n' "${OUTPUT_PREFIX}_simulator_name=$SIMULATOR_NAME"
            printf '%s\n' "${OUTPUT_PREFIX}_simulator_udid=$SIMULATOR_UDID"
        } >> "$GITHUB_OUTPUT"
    else
        echo "GITHUB_OUTPUT not set; printing outputs for local run:"
        printf '%s\n' "${OUTPUT_PREFIX}_simulator_name=$SIMULATOR_NAME"
        printf '%s\n' "${OUTPUT_PREFIX}_simulator_udid=$SIMULATOR_UDID"
    fi
    echo "Successfully configured ${PLATFORM_KEY} Simulator: name='$SIMULATOR_NAME' udid='${SIMULATOR_UDID:-N/A}'"
}

# Call the function with the provided arguments
find_simulator "$PLATFORM_KEY" "$DEVICE_MATCH" "$FALLBACK_DEVICE" "$OUTPUT_PREFIX"