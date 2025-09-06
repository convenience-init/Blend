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
    if ! echo "$device_name" | grep -q '^[a-zA-Z0-9 ()-]\+$'; then
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

# Helper function to boot simulator if needed
boot_simulator_if_needed() {
    local name="$1"
    local udid="$2"
    local label="$3"
    
    echo "Checking boot status for $label: $name ($udid)"
    
    # Check current state by parsing xcrun simctl list devices output
    local state
    state=$(xcrun simctl list devices 2>/dev/null | grep "$udid" | sed 's/.*(\([^)]*\)).*/\1/' | tr -d ' ')
    
    if [ "$state" = "Booted" ]; then
        echo "✓ $label is already booted: $name ($udid)"
        return 0
    fi
    
    echo "Booting $label: $name ($udid)"
    if ! xcrun simctl boot "$udid"; then
        echo "ERROR: Failed to boot $label with xcrun simctl boot"
        echo "Simulator UDID: $udid"
        echo "Available devices list:"
        xcrun simctl list devices available || true
        return 1
    fi
    
    echo "Waiting for $label to be fully booted..."
    if ! timeout_bootstatus "$name" "$udid" "$label booting"; then
        echo "ERROR: $label did not reach booted state"
        return 1
    fi
    
    echo "✓ $label is booted and ready: $name ($udid)"
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

    # Run xcrun command once and capture both output and exit code
    # Use command substitution to capture both stdout and stderr
    echo "Running: xcrun simctl list --json devices available"
    XCRUN_PATH=$(command -v xcrun)
    echo "xcrun executable path: ${XCRUN_PATH:-<not found>}"
    
    # Create temporary file for stderr capture
    ERR_TEMP_FILE=$(mktemp) || {
        echo "ERROR: Failed to create temporary file for stderr capture"
        exit 1
    }
    
    # Run xcrun with stdout captured to JSON_OUTPUT and stderr redirected to temp file
    if ! JSON_OUTPUT=$(xcrun simctl list --json devices available 2>"$ERR_TEMP_FILE"); then
        EXIT_CODE=$?
        # Read stderr from temp file
        ERR_OUTPUT=$(cat "$ERR_TEMP_FILE" 2>/dev/null || echo "Failed to read stderr from temp file")
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
        # Clean up temp file
        rm -f "$ERR_TEMP_FILE"
        exit $EXIT_CODE
    fi
    
    # Clean up temp file on success
    rm -f "$ERR_TEMP_FILE"
    
    # JSON_OUTPUT now contains only stdout (clean JSON), ERR_OUTPUT is not used for successful execution

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

    # Track if we used fallback
    USED_FALLBACK=false
    if [ -n "${SIMULATOR_LINE:-}" ]; then
        SIMULATOR_NAME="$(echo "$SIMULATOR_LINE" | cut -f1)"
        SIMULATOR_UDID="$(echo "$SIMULATOR_LINE" | cut -f2)"
        echo "Found available ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
    else
        USED_FALLBACK=true
        echo "No available ${PLATFORM_KEY} simulators found, attempting fallback to '$FALLBACK_DEVICE'..."
        # Fallback logic - try to find a simulator that matches the fallback device name
        if ! SIMULATOR_LINE=$(echo "$JSON_OUTPUT" | jq --arg platform_key "$PLATFORM_KEY" --arg device_match "$FALLBACK_DEVICE" -r "$JQ_QUERY" 2>/dev/null | head -1); then
            echo "ERROR: jq parsing for fallback device failed"
            echo "Available devices list:"
            xcrun simctl list devices available || true
            exit 1
        fi
        
        if [ -n "${SIMULATOR_LINE:-}" ]; then
            SIMULATOR_NAME="$(echo "$SIMULATOR_LINE" | cut -f1)"
            SIMULATOR_UDID="$(echo "$SIMULATOR_LINE" | cut -f2)"
            echo "Fallback to ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
        else
            # No simulators found at all, create one
            echo "No ${PLATFORM_KEY} simulators found, creating a new one..."
            
            # Determine the device type and runtime based on platform
            case "$PLATFORM_KEY" in
                "iOS")
                    DEVICE_TYPE="iPhone"
                    RUNTIME=$(xcrun simctl list runtimes | grep "iOS" | grep "ready" | tail -1 | awk '{print $2}' | tr -d '()')
                    ;;
                "tvOS")
                    DEVICE_TYPE="Apple TV"
                    RUNTIME=$(xcrun simctl list runtimes | grep "tvOS" | grep "ready" | tail -1 | awk '{print $2}' | tr -d '()')
                    ;;
                *)
                    echo "ERROR: Unsupported platform: $PLATFORM_KEY"
                    exit 1
                    ;;
            esac
            
            if [ -z "$RUNTIME" ]; then
                echo "ERROR: No suitable runtime found for $PLATFORM_KEY"
                echo "Available runtimes:"
                xcrun simctl list runtimes || true
                echo ""
                echo "For CI environments, you may need to install the $PLATFORM_KEY runtime:"
                echo "  - GitHub Actions: Use 'xcodes' or 'simctl' to install runtimes"
                echo "  - Local development: Install additional simulator runtimes in Xcode"
                echo ""
                echo "To install tvOS runtime in CI (example for GitHub Actions):"
                echo "  - name: Install tvOS Runtime"
                echo "    run: |"
                echo "      xcrun simctl runtime add tvOS"
                echo "      # or use xcodes: xcodes runtimes install tvOS"
                exit 1
            fi
            
            # Create simulator with a unique name
            SIMULATOR_NAME="${DEVICE_TYPE} CI $(date +%s)"
            echo "Creating ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' with runtime $RUNTIME"
            
            if ! SIMULATOR_UDID=$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE" "$RUNTIME"); then
                echo "ERROR: Failed to create ${PLATFORM_KEY} simulator"
                echo "Available device types:"
                xcrun simctl list devicetypes || true
                echo "Available runtimes:"
                xcrun simctl list runtimes || true
                exit 1
            fi
            
            echo "Created ${PLATFORM_KEY} simulator: '$SIMULATOR_NAME' (UDID: $SIMULATOR_UDID)"
            USED_FALLBACK=false  # Reset since we created a new simulator
        fi
        
        # Ensure fallback device is booted
        if ! boot_simulator_if_needed "$SIMULATOR_NAME" "$SIMULATOR_UDID" "fallback simulator"; then
            BOOT_EXIT_CODE=$?
            exit $BOOT_EXIT_CODE
        fi
    fi

    # Note: Fallback device is already booted above, so we only need to handle the primary device here
    if [ -n "$SIMULATOR_UDID" ] && [ "$USED_FALLBACK" = false ]; then
        if ! boot_simulator_if_needed "$SIMULATOR_NAME" "$SIMULATOR_UDID" "simulator"; then
            BOOT_EXIT_CODE=$?
            exit $BOOT_EXIT_CODE
        fi
    fi

    # Ensure simulator is fully booted (after idempotent boot above)
    echo ""
    echo "Ensuring simulator is fully booted..."
    if ! timeout_bootstatus "$SIMULATOR_NAME" "$SIMULATOR_UDID" "Simulator booting"; then
        echo "ERROR: Simulator did not reach booted state"
        exit 1
    fi
    echo "✓ Simulator is booted and ready"

    # Print final selected simulator information
    echo "Final selected ${PLATFORM_KEY} simulator:"
    echo "Name: $SIMULATOR_NAME"
    echo "UDID: $SIMULATOR_UDID"
    echo ""
    # CI outputs
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        {
            echo "${OUTPUT_PREFIX}_name=${SIMULATOR_NAME}"
            echo "${OUTPUT_PREFIX}_udid=${SIMULATOR_UDID}"
        } >> "$GITHUB_OUTPUT"
        echo "Wrote outputs to GITHUB_OUTPUT with prefix '${OUTPUT_PREFIX}_'."
    fi
    if [ -n "${GITHUB_ENV:-}" ]; then
        {
            echo "SIM_NAME=${SIMULATOR_NAME}"
            echo "SIM_UDID=${SIMULATOR_UDID}"
        } >> "$GITHUB_ENV"
        echo "Wrote environment variables to GITHUB_ENV."
    fi
    export SIMULATOR_NAME SIMULATOR_UDID
    echo "You can now run your tests or build your app targeting this simulator."
    echo "For example, to run tests with xcodebuild:"
    echo "  xcodebuild test -destination 'id=$SIMULATOR_UDID'"
    echo ""
    echo "To open the simulator in Xcode, use the following menu:"
    echo "  Window > Devices and Simulators > Select your simulator > Open Console"
    echo ""
    echo "To uninstall the app from the simulator:"
    echo "  xcrun simctl uninstall $SIMULATOR_UDID <app_bundle_identifier>"
    echo ""
    echo "To shutdown the simulator:"
    echo "  xcrun simctl shutdown $SIMULATOR_UDID"
    echo ""
    echo "To delete the simulator (if no longer needed):"
    echo "  xcrun simctl delete $SIMULATOR_UDID"
    echo ""
    echo "=== Simulator Discovery Completed ==="
}

# Call the main function with parsed parameters
find_simulator "$PLATFORM_KEY" "$DEVICE_MATCH" "$FALLBACK_DEVICE" "$OUTPUT_PREFIX"
