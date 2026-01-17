#!/bin/bash

# ==============================================================================
#
# AWS Token Utility (awstok)
#
# A self-contained script to manage AWS CodeArtifact token refreshes for NuGet.
# Designed to be portable and suitable for packaging with Homebrew.
#
# ==============================================================================

# --- Path Setup ---
# Define standard paths for Homebrew (Apple Silicon & Intel) and .NET tools
HOMEBREW_PREFIX_ARM="/opt/homebrew"
HOMEBREW_PREFIX_INTEL="/usr/local"
DOTNET_TOOLS_PATH="$HOME/.dotnet/tools"
DOTNET_INSTALL_PATH="/usr/local/share/dotnet"

# Prepend common tool locations to the PATH to ensure commands are found
export PATH="${HOMEBREW_PREFIX_ARM}/bin:${HOMEBREW_PREFIX_INTEL}/bin:${DOTNET_INSTALL_PATH}:${DOTNET_TOOLS_PATH}:$PATH"


# --- Configuration ---
SAML2AWS_PROFILE="tlb-dev-2"
CODEARTIFACT_DOMAIN="tlb-test-code-artifact-domain"
CODEARTIFACT_OWNER="690772145391"
CODEARTIFACT_REGION="eu-west-2"
NUGET_SOURCE_NAME="tlb-test-code-artifact-domain/internal-nuget-repo"
LOG_FILE="$HOME/awstok.log"


# --- Logging and Notifications ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_notification() {
    # Arguments: $1=Subtitle, $2=Message
    osascript -e "display notification \"$2\" with title \"AWS Token Utility\" subtitle \"$1\""
}

show_login_prompt() {
    SELF_PATH=$(realpath "$0")
    osascript -e '
        tell application "System Events" 
            activate
            display dialog "Token refresh failed or timed out. Do you want to run the interactive login now?" ¬
            with title "AWS Token Utility" ¬
            with icon caution ¬
            buttons {"No, later", "Yes, run login"} default button "Yes, run login"
            if button returned of result is "Yes, run login" then
                tell application "Terminal" 
                    activate
                    do script "'"$SELF_PATH"' login"
                end tell
            end if
        end tell
    '
}


# ==============================================================================
# --- Core Logic Functions ---
# ==============================================================================

#
# 1. Non-interactive refresh cycle
#
function main_refresh() {
    log "🔄 Starting non-interactive token refresh..."

    # Check if AWS credentials are valid
    if ! AWS_PROFILE=$SAML2AWS_PROFILE aws sts get-caller-identity &> /dev/null; then
        log "❌ AWS credentials expired or invalid. Attempting auto-login..."
        # Try non-interactive login first (will use keychain if available)
        if ! saml2aws login -a $SAML2AWS_PROFILE --skip-prompt >> "$LOG_FILE" 2>&1; then
            log "⚠️ Non-interactive login failed - MFA may be required. Aborting."
            send_notification "MFA Required" "Automatic refresh failed. Please run 'awstok login' manually."
            return 1
        fi
        log "✅ Keychain login successful."
    fi

    log "✅ AWS credentials seem valid."

    # Get CodeArtifact token
    log "🔑 Getting CodeArtifact token..."
    TOKEN=$(AWS_PROFILE=$SAML2AWS_PROFILE aws codeartifact get-authorization-token \
        --domain "$CODEARTIFACT_DOMAIN" \
        --domain-owner "$CODEARTIFACT_OWNER" \
        --region "$CODEARTIFACT_REGION" \
        --query authorizationToken \
        --output text 2>&1)

    if [ $? -ne 0 ] || [ -z "$TOKEN" ]; then
        log "❌ Failed to get CodeArtifact token: $TOKEN"
        send_notification "Refresh Failed" "Could not retrieve CodeArtifact token. Check logs."
        return 1
    fi
    log "✅ CodeArtifact token retrieved successfully."

    # Update NuGet source
    log "📦 Updating NuGet source '$NUGET_SOURCE_NAME'..."
    UPDATE_RESULT=$(dotnet nuget update source "$NUGET_SOURCE_NAME" \
        --username aws \
        --password "$TOKEN" \
        --store-password-in-clear-text 2>&1)

    if [ $? -eq 0 ]; then
        log "✅ NuGet source updated successfully."
        send_notification "Refresh Successful" "Your NuGet token has been updated."
    else
        log "❌ Failed to update NuGet source: $UPDATE_RESULT"
        send_notification "Refresh Failed" "Could not update the NuGet source. Check logs."
    fi
}

#
# 2. Interactive user login
#
function interactive_login() {
    echo "🔐 Logging in to AWS with saml2aws for profile '$SAML2AWS_PROFILE'ப்பான"
    echo "📱 Please have your authenticator app ready for MFA."
    echo ""

    if saml2aws login -a $SAML2AWS_PROFILE; then
        echo ""
        echo "✅ Login successful! AWS credentials refreshed."
        echo "🔄 Automatically refreshing NuGet token..."
        main_refresh

    else
        echo ""
        echo "❌ Login failed."
    fi
}

#
# 3. Check and refresh with timeout and GUI prompt
#
function check_and_notify() {
    # Define path for gtimeout
    GTIMEOUT_CMD=$(command -v gtimeout)

    # Check if gtimeout is available
    if [ -z "$GTIMEOUT_CMD" ]; then
        log "❌ gtimeout command not found. Please install coreutils with 'brew install coreutils'"
        send_notification "Error" "gtimeout not found. Please run 'brew install coreutils'"
        exit 1
    fi

    log "🔄 Attempting to refresh AWS token with a 2-minute timeout..."

    # Run the refresh command with a timeout.
    if $GTIMEOUT_CMD 120 "$0" refresh; then
        log "✅ Timed refresh successful."
        # Notification is sent by main_refresh()
    else
        log "❌ Timed refresh command failed or timed out."
        show_login_prompt
    fi
}

#
# 4. Get and display the current token
#
function get_token() {
    local config_file="$HOME/.nuget/NuGet/NuGet.Config"

    echo "🔍 Searching for AWS CodeArtifact token in global NuGet config..."
    echo "   ($config_file)"
    echo ""

    if [ ! -f "$config_file" ]; then
        echo "❌ Global NuGet config file not found."
        return 1
    fi

    # Try with xmllint if available
    if command -v xmllint &> /dev/null; then
        local token=$(xmllint --xpath "string(//configuration/packageSourceCredentials/*[local-name()='tlb-test-code-artifact-domain-internal-nuget-repo']/add[@key='ClearTextPassword']/@value)" "$config_file" 2>/dev/null)
    fi

    # Fallback to grep/sed if xmllint fails or is not present
    if [ -z "$token" ]; then
        token=$(grep -A 5 "$CODEARTIFACT_DOMAIN" "$config_file" | grep "ClearTextPassword" | sed -n 's/.*value="\([^"]*\)".*/\1/p')
    fi

    if [ -n "$token" ]; then
        echo "✅ Token found!"
        echo "--------------------------------------------------"
        echo "$token"
        echo "--------------------------------------------------"
        echo "Token length: ${#TOKEN} characters"
    else
        echo "❌ Token not found in NuGet config."
        echo "➡️  Run 'awstok refresh' to generate and store a new token."
    fi
}


#
# 5. Display help message
#
function show_help() {
    echo "AWS Token Utility"
    echo "A tool to manage AWS CodeArtifact tokens for NuGet."
    echo ""
    echo "Usage: $0 {command}"
    echo ""
    echo "Commands:"
    echo "  refresh       - Runs a single, non-interactive refresh cycle."
    echo "  login         - Runs an interactive login to refresh AWS credentials via MFA."
    echo "  gt            - Extracts and displays the current token from your NuGet config."
    echo "  help          - Shows this help message."
    echo ""
    echo "Logs are stored in: $LOG_FILE"
}


# ==============================================================================
# --- Main Entrypoint ---
# ==============================================================================

case "$1" in
    refresh)
        main_refresh
        ;;    login)
        interactive_login
        ;;    check)
        check_and_notify
        ;;    gt)
        get_token
        ;;    help|*)
        show_help
        ;;esac
