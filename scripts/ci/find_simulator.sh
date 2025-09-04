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
    
    # Create a secure temporary marker file for timeout detection
    local marker_file
    marker_file=$(mktemp) || {
        echo "ERROR: Failed to create temporary marker file"
        return 1
    }
    
    # Start bootstatus in background
    xcrun simctl bootstatus "$simulator_udid" -b 2>&1 &
    local bootstatus_pid=$!
    
    # Start timeout sleeper in background with marker file path
    (
        sleep "$TIMEOUT_SEC"
        # Check if bootstatus is still running before attempting to kill
        if kill -0 "$bootstatus_pid" 2>/dev/null; then
            echo "TIMEOUT: bootstatus command timed out after ${TIMEOUT_SEC}s for $simulator_name ($simulator_udid)"
            # Write timeout marker to file
            echo "TIMEOUT" > "$marker_file"
            # Kill the bootstatus process
            kill "$bootstatus_pid" 2>/dev/null || true
        fi
    ) &
    local sleeper_pid=$!
    
    # Wait for bootstatus to finish
    local exit_code
    wait "$bootstatus_pid" 2>/dev/null
    exit_code=$?
    
    # Clean up sleeper process if still running
    if kill -0 "$sleeper_pid" 2>/dev/null; then
        kill "$sleeper_pid" 2>/dev/null || true
        wait "$sleeper_pid" 2>/dev/null || true
    fi
    
    # Check for timeout marker file to deterministically detect timeout
    local timed_out=false
    if [ -f "$marker_file" ] && [ "$(cat "$marker_file" 2>/dev/null)" = "TIMEOUT" ]; then
        timed_out=true
    fi
    
    # Clean up marker file
    rm -f "$marker_file"
    
    # Handle timeout case
    if [ "$timed_out" = true ]; then
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

# Helper function to validate device name format
validate_device_name() {
    local device_name="$1"
    
    # Check if device name is non-empty
    if [ -z "$device_name" ]; then
        echo "ERROR: Device name is empty"
        return 1
    fi
    
    # Check for control characters or other invalid characters
    if echo "$device_name" | grep -q '[[:cntrl:]]'; then
        echo "ERROR: Device name contains control characters: '$device_name'"
        return 1
    fi
    
    # Check for basic pattern: letters, numbers, spaces, hyphens, parentheses
    if ! echo "$device_name" | grep -q '^[a-zA-Z0-9 ()\-]\+$'; then
        echo "ERROR: Device name contains invalid characters (only letters, numbers, spaces, hyphens, parentheses allowed): '$device_name'"
        return 1
    fi
    
    # Check minimum length
    if [ ${#device_name} -lt 3 ]; then
        echo "ERROR: Device name is too short (minimum 3 characters): '$device_name'"
        return 1
    fi
    
    return 0
}

# Helper function to validate and clean UDID
validate_and_clean_udid() {
    local raw_udid="$1"
    local source="$2"
    
    # Trim whitespace
    local cleaned_udid
    cleaned_udid=$(echo "$raw_udid" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if empty after trimming
    if [ -z "$cleaned_udid" ]; then
        return 1
    fi
    
    # Check if it's "null"
    if [ "$cleaned_udid" = "null" ]; then
        return 1
    fi
    
    # Basic UUID pattern validation (8-4-4-4-12 format with hyphens)
    if ! echo "$cleaned_udid" | grep -q '^[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}$'; then
        return 1
    fi
    
    echo "$cleaned_udid"
    return 0
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

    # Create secure temporary files for capturing command output
    # Use traps to ensure cleanup on any exit or signal
    STDOUT_TEMP=""
    STDERR_TEMP=""
    
    # Function to clean up temp files
    cleanup_temp_files() {
        [ -n "$STDOUT_TEMP" ] && [ -f "$STDOUT_TEMP" ] && rm -f "$STDOUT_TEMP"
        [ -n "$STDERR_TEMP" ] && [ -f "$STDERR_TEMP" ] && rm -f "$STDERR_TEMP"
    }
    
    # Register cleanup function for all exit paths and signals
    trap cleanup_temp_files EXIT INT TERM HUP
    
    # Create stdout temp file
    STDOUT_TEMP=$(mktemp) || {
        echo "ERROR: Failed to create temporary file for stdout capture"
        echo "Command: mktemp"
        echo "Exit code: $?"
        echo "This may indicate disk space issues or permissions problems"
        exit 1
    }
    
    # Create stderr temp file
    STDERR_TEMP=$(mktemp) || {
        echo "ERROR: Failed to create temporary file for stderr capture"
        echo "Command: mktemp"
        echo "Exit code: $?"
        echo "This may indicate disk space issues or permissions problems"
        exit 1
    }
    
    # Run xcrun command once and capture both output and exit code
    # Use separate temp files to avoid mixing stderr with JSON stdout
    echo "Running: xcrun simctl list --json devices available"
    XCRUN_PATH=$(command -v xcrun)
    echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
    
    # Run xcrun with stdout and stderr separated
    xcrun simctl list --json devices available >"$STDOUT_TEMP" 2>"$STDERR_TEMP"
    EXIT_CODE=$?
    
    # Read outputs from temp files
    JSON_OUTPUT=$(cat "$STDOUT_TEMP")
    ERR_OUTPUT=$(cat "$STDERR_TEMP")
    
    # Check if command failed
    if [ $EXIT_CODE -ne 0 ]; then
        echo "ERROR: xcrun simctl list failed with exit code $EXIT_CODE"
        echo "Command run: xcrun simctl list --json devices available"
        echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
        echo ""
        echo "=== Captured stderr output (first 20 lines) ==="
        echo "$ERR_OUTPUT" | head -20
        if [ $(echo "$ERR_OUTPUT" | wc -l) -gt 20 ]; then
            echo "... (truncated, $(echo "$ERR_OUTPUT" | wc -l) total lines)"
        fi
        echo ""
        echo "=== Captured stdout output (first 20 lines) ==="
        echo "$JSON_OUTPUT" | head -20
        if [ $(echo "$JSON_OUTPUT" | wc -l) -gt 20 ]; then
            echo "... (truncated, $(echo "$JSON_OUTPUT" | wc -l) total lines)"
        fi
        echo ""
        echo "=== Full captured outputs ==="
        echo "xcrun stderr output:"
        echo "$ERR_OUTPUT"
        echo "xcrun stdout output:"
        echo "$JSON_OUTPUT"
        echo ""
        echo "Available devices list:"
        xcrun simctl list devices available || true
        # Cleanup will be handled by trap
        exit $EXIT_CODE
    fi
    
    # Cleanup temp files on success (trap will handle this, but explicit cleanup for clarity)
    cleanup_temp_files

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
    JQ_PATH=$(command -v jq)
    echo "jq executable path: ${JQ_PATH:-<not found>}"
    
    # Validate JSON structure first
    if ! echo "$JSON_OUTPUT" | jq -e '.devices' >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON structure - missing .devices key"
        echo "JSON output was:"
        echo "$JSON_OUTPUT"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit 1
    fi
    
    # Store jq query in variable to avoid duplication
    JQ_QUERY='.devices
        | to_entries[]
        | select(.key | contains($platform_key))
        | .value[]
        | select(.name | contains($device_match))
        | select(.isAvailable == true)
        | select(.state == "Shutdown" or .state == "Booted")
        | [.name, .udid] | @tsv'
    
    # Build the jq command for logging
    JQ_COMMAND="jq --arg platform_key \"$PLATFORM_KEY\" --arg device_match \"$DEVICE_MATCH\" -r \"$JQ_QUERY\""
    echo "Running: echo \"<JSON_OUTPUT>\" | $JQ_COMMAND | head -1"
    
    if ! SIMULATOR_LINE=$(echo "$JSON_OUTPUT" | jq --arg platform_key "$PLATFORM_KEY" --arg device_match "$DEVICE_MATCH" -r "$JQ_QUERY" 2>/dev/null | head -1); then
        # Capture the actual jq error
        JQ_ERROR=$(echo "$JSON_OUTPUT" | jq --arg platform_key "$PLATFORM_KEY" --arg device_match "$DEVICE_MATCH" -r "$JQ_QUERY" 2>&1 >/dev/null)
        echo "ERROR: jq parsing failed"
        echo "jq error output: $JQ_ERROR"
        echo "Platform key: '$PLATFORM_KEY'"
        echo "Device match: '$DEVICE_MATCH'"
        echo "JSON structure preview:"
        echo "$JSON_OUTPUT" | jq '.devices | keys' 2>/dev/null || echo "Cannot preview JSON keys"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        exit 1
    fi

    if [ -n "${SIMULATOR_LINE:-}" ]; then
        SIMULATOR_NAME="$(echo "$SIMULATOR_LINE" | cut -f1)"
        SIMULATOR_UDID="$(echo "$SIMULATOR_LINE" | cut -f2)"
        echo "Found available ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
    else
        echo "No available ${PLATFORM_KEY} simulators found, attempting fallback to '$FALLBACK_DEVICE'..."

        # Validate fallback device name before attempting resolution
        if ! validate_device_name "$FALLBACK_DEVICE"; then
            echo "ERROR: Invalid fallback device name format"
            echo "Platform: $PLATFORM_KEY"
            echo "Device: $FALLBACK_DEVICE"
            echo ""
            echo "Available devices from JSON:"
            echo "$JSON_OUTPUT" | jq '.devices' 2>/dev/null || echo "JSON parsing failed"
            echo ""
            echo "Available devices from xcrun simctl:"
            xcrun simctl list devices available || true
            exit 1
        fi

        # Resolve fallback UDID from JSON first
        echo "Attempting JSON UDID resolution for device: $FALLBACK_DEVICE"
        JQ_PATH=$(command -v jq)
        echo "jq executable path: ${JQ_PATH:-<not found>}"
        
        # Validate JSON structure first
        if ! echo "$JSON_OUTPUT" | jq -e '.devices' >/dev/null 2>&1; then
            echo "WARNING: Invalid JSON structure for UDID resolution - missing .devices key"
            echo "Skipping JSON UDID resolution, will try xcrun simctl parsing as fallback"
            raw_json_udid=""
        else
            # Store jq query in variable to avoid duplication
            JQ_UDID_QUERY='.devices
                | to_entries[]
                | select(.key | contains($platform))
                | .value[]
                | select(.name == $device and .isAvailable == true)
                | .udid'
            
            # Build the jq command for logging
            JQ_COMMAND="jq -r --arg platform \"$PLATFORM_KEY\" --arg device \"$FALLBACK_DEVICE\" \"$JQ_UDID_QUERY\""
            echo "Running: echo \"<JSON_OUTPUT>\" | $JQ_COMMAND | head -n 1"
            
            local raw_json_udid
            if ! raw_json_udid=$(echo "$JSON_OUTPUT" | jq -r --arg platform "$PLATFORM_KEY" --arg device "$FALLBACK_DEVICE" "$JQ_UDID_QUERY" 2>"$STDERR_TEMP" | head -n 1); then
                EXIT_CODE=$?
                STDERR_OUTPUT=$(cat "$STDERR_TEMP")
                echo "WARNING: JSON UDID resolution jq command failed with exit code $EXIT_CODE"
                echo "Command run: echo \"<JSON_OUTPUT>\" | $JQ_COMMAND | head -n 1"
                echo "jq stderr output: $STDERR_OUTPUT"
                echo "This is not fatal - will try xcrun simctl parsing as fallback"
                raw_json_udid=""
            fi
        fi

        # Validate JSON UDID resolution
        if SIMULATOR_UDID=$(validate_and_clean_udid "$raw_json_udid" "JSON resolution"); then
            echo "Successfully resolved UDID from JSON: $SIMULATOR_UDID"
        else
            echo "JSON UDID resolution failed or returned invalid UDID, trying xcrun simctl list parsing..."
            
            # Try parsing xcrun simctl list output
            local raw_simctl_udid
            raw_simctl_udid="$(
                xcrun simctl list devices available 2>/dev/null | \
                grep -F "$FALLBACK_DEVICE" | \
                sed -n 's/.*(\([^)]*\)).*/\1/p' | \
                head -n 1 | \
                tr -d '[:space:]'
            )"
            
            # Validate simctl UDID resolution
            if ! SIMULATOR_UDID=$(validate_and_clean_udid "$raw_simctl_udid" "xcrun simctl parsing"); then
                # Both resolution methods failed - provide comprehensive error information
                echo "ERROR: Could not resolve valid UDID for fallback device"
                echo "Platform: $PLATFORM_KEY"
                echo "Attempted Device: $FALLBACK_DEVICE"
                echo ""
                echo "=== JSON Resolution Details ==="
                echo "Raw JSON UDID result: '${raw_json_udid:-<empty>}'"
                if [ -n "$raw_json_udid" ] && [ "$raw_json_udid" != "null" ]; then
                    if ! echo "$raw_json_udid" | grep -q '^[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}$'; then
                        echo "JSON validation error: UDID does not match UUID format"
                    else
                        echo "JSON validation error: Unknown validation failure"
                    fi
                else
                    echo "JSON validation error: Empty or null UDID"
                fi
                echo ""
                echo "JSON devices matching platform '$PLATFORM_KEY':"
                echo "$JSON_OUTPUT" | jq --arg platform "$PLATFORM_KEY" '
                    .devices
                    | to_entries[]
                    | select(.key | contains($platform))
                    | .key' 2>/dev/null || echo "JSON parsing failed"
                echo ""
                echo "All available devices from JSON:"
                echo "$JSON_OUTPUT" | jq '.devices | to_entries[] | .key' 2>/dev/null || echo "JSON parsing failed"
                echo ""
                echo "=== xcrun simctl Resolution Details ==="
                echo "Raw simctl UDID result: '${raw_simctl_udid:-<empty>}'"
                if [ -n "$raw_simctl_udid" ] && [ "$raw_simctl_udid" != "null" ]; then
                    if ! echo "$raw_simctl_udid" | grep -q '^[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}$'; then
                        echo "simctl validation error: UDID does not match UUID format"
                    else
                        echo "simctl validation error: Unknown validation failure"
                    fi
                else
                    echo "simctl validation error: Empty or null UDID"
                fi
                echo ""
                echo "xcrun simctl devices available output:"
                xcrun simctl list devices available 2>/dev/null || echo "xcrun command failed"
                echo ""
                echo "Lines containing '$FALLBACK_DEVICE' from simctl output:"
                xcrun simctl list devices available 2>/dev/null | grep -F "$FALLBACK_DEVICE" || echo "No matches found"
                echo ""
                echo "=== Resolution Summary ==="
                echo "Both JSON and simctl resolution methods failed to provide a valid UUID-formatted UDID"
                echo "Please verify that '$FALLBACK_DEVICE' exists and is available on this system"
                exit 1
            fi
        fi
        
        SIMULATOR_NAME="$FALLBACK_DEVICE"
        echo "Using fallback ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"

        # Ensure fallback device is booted for stable UDID
        echo "Ensuring fallback simulator is booted: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        XCRUN_PATH=$(command -v xcrun)
        echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
        
        # Check current state first
        echo "Checking current state of simulator: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        if ! CURRENT_STATE="$(xcrun simctl list --json devices 2>"$STDERR_TEMP" | jq -r --arg udid "$SIMULATOR_UDID" '.devices | to_entries[] | .value[] | select(.udid == $udid) | .state // empty' 2>>"$STDERR_TEMP")"; then
            STDERR_OUTPUT=$(cat "$STDERR_TEMP")
            echo "WARNING: Failed to check simulator state, proceeding with boot attempt"
            echo "xcrun simctl list stderr: $STDERR_OUTPUT"
            CURRENT_STATE=""
        fi
        
        if [ "$CURRENT_STATE" != "Booted" ]; then
            echo "Fallback simulator not booted; attempting boot..."
            echo "Running: xcrun simctl boot \"$SIMULATOR_UDID\""
            if ! xcrun simctl boot "$SIMULATOR_UDID" >"$STDOUT_TEMP" 2>"$STDERR_TEMP"; then
                EXIT_CODE=$?
                STDOUT_OUTPUT=$(cat "$STDOUT_TEMP")
                STDERR_OUTPUT=$(cat "$STDERR_TEMP")
                echo "ERROR: Failed to boot fallback simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                echo "Command run: xcrun simctl boot \"$SIMULATOR_UDID\""
                echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
                echo "Exit code: $EXIT_CODE"
                echo ""
                echo "=== Captured stdout output ==="
                echo "$STDOUT_OUTPUT"
                echo ""
                echo "=== Captured stderr output ==="
                echo "$STDERR_OUTPUT"
                echo ""
                echo "Available devices list:"
                xcrun simctl list devices available || true
                echo ""
                echo "Device details from simctl list:"
                xcrun simctl list devices 2>/dev/null | grep -F -A 2 -B 2 "$SIMULATOR_NAME" || true
                # Cleanup will be handled by trap
                exit $EXIT_CODE
            fi
            echo "Waiting for fallback simulator to be ready..."
            if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Fallback simulator readiness check"; then
                echo "ERROR: Failed to reach booted state for fallback simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -F -A 2 -B 2 "$SIMULATOR_NAME" || true
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
        XCRUN_PATH=$(command -v xcrun)
        echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
        
        # Check current state first
        echo "Checking current state of simulator: $SIMULATOR_NAME ($SIMULATOR_UDID)"
        if ! CURRENT_STATE="$(xcrun simctl list --json devices 2>"$STDERR_TEMP" | jq -r --arg udid "$SIMULATOR_UDID" '.devices | to_entries[] | .value[] | select(.udid == $udid) | .state // empty' 2>>"$STDERR_TEMP")"; then
            STDERR_OUTPUT=$(cat "$STDERR_TEMP")
            echo "WARNING: Failed to check simulator state, proceeding with boot attempt"
            echo "xcrun simctl list stderr: $STDERR_OUTPUT"
            CURRENT_STATE=""
        fi
        
        if [ "$CURRENT_STATE" != "Booted" ]; then
            echo "Simulator not booted; attempting boot..."
            echo "Running: xcrun simctl boot \"$SIMULATOR_UDID\""
            if ! xcrun simctl boot "$SIMULATOR_UDID" >"$STDOUT_TEMP" 2>"$STDERR_TEMP"; then
                EXIT_CODE=$?
                STDOUT_OUTPUT=$(cat "$STDOUT_TEMP")
                STDERR_OUTPUT=$(cat "$STDERR_TEMP")
                echo "ERROR: Failed to boot simulator '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                echo "Command run: xcrun simctl boot \"$SIMULATOR_UDID\""
                echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
                echo "Exit code: $EXIT_CODE"
                echo ""
                echo "=== Captured stdout output ==="
                echo "$STDOUT_OUTPUT"
                echo ""
                echo "=== Captured stderr output ==="
                echo "$STDERR_OUTPUT"
                echo ""
                echo "Available devices list:"
                xcrun simctl list devices available || true
                echo ""
                echo "Device details from simctl list:"
                xcrun simctl list devices 2>/dev/null | grep -F -A 2 -B 2 "$SIMULATOR_NAME" || true
                # Cleanup will be handled by trap
                exit $EXIT_CODE
            fi
            echo "Waiting for simulator to be ready..."
            if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Primary simulator readiness check"; then
                echo "ERROR: Failed to reach booted state for '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
                xcrun simctl list devices available || true
                xcrun simctl list devices 2>/dev/null | grep -F -A 2 -B 2 "$SIMULATOR_NAME" || true
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