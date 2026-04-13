#!/usr/bin/env bash

# ===== USAGE =====
# Run with parameters:
#   ./cleanup_users_final.sh <API_BASE_URL> <MONTHS_LIMIT> [API_TOKEN]
#
# Examples:
#   1. With all parameters:
#      ./cleanup_users_final.sh https://your-app-url.com/api 6 your-api-token
#
#   2. With required parameters (will prompt for API_TOKEN):
#      ./cleanup_users_final.sh https://your-app-url.com/api 6
#
# You can also set API_TOKEN via environment variable:
#   export API_TOKEN="your-api-token"


# ===== INPUT HANDLING =====
# Check for minimum required arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <API_BASE_URL> <MONTHS_LIMIT> [API_TOKEN]"
    exit 1
fi

# Use environment variables with command-line argument overrides
API_BASE_URL=${1:-${API_BASE_URL:-""}}
MONTHS_LIMIT=${2:-${MONTHS_LIMIT:-6}}  # Default to 6 months if not specified

# Handle API_TOKEN with security warning
if [ -n "$3" ]; then
    echo "Provided API_TOKEN via argument, leaking the TOKEN to the history."
    echo "Recommended to provide via environment variable (\"API_TOKEN\") or interaction"
    API_TOKEN=$3
else
    # Try to get from environment variable
    API_TOKEN=${API_TOKEN:-""}
fi

# If API_TOKEN is still empty, prompt for it
if [ -z "$API_TOKEN" ]; then
    echo "Please provide an API_TOKEN (CLI ARG > Env API_TOKEN > interactive)"
    read -r line
    API_TOKEN="$line"
fi

# Validate required parameters
if [[ -z "$API_BASE_URL" || -z "$API_TOKEN" ]]; then
    echo "Error: Missing required parameters"
    echo "Please set environment variables or provide command-line arguments:"
    echo "  API_BASE_URL: The base URL of the API"
    echo "  API_TOKEN: Your API authentication token"
    echo "  MONTHS_LIMIT: (Optional) Threshold for inactive users in months (default: 6)"
    exit 1
fi

# Remove trailing slash from API_BASE_URL if present
API_BASE_URL=${API_BASE_URL%/}
USERS_ENDPOINT="$API_BASE_URL/settings/users"
DELETE_ENDPOINT="$API_BASE_URL/settings/users/delete"

# ===== DEPENDENCY CHECK =====
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed."
    echo "Please install jq."
    exit 1
fi

# Initialize variables to store data instead of using temp files
USERS_TO_REMOVE=0
USER_IDS_JSON="[]"
USER_LIST="USERS TO BE REMOVED FROM TENANT (Inactive for more than $MONTHS_LIMIT months):
--------------------------------------------------------------
ID | Full Name | Last Login Date | Months Inactive
--------------------------------------------------------------"

# ===== GET USERS =====
echo "Fetching users..."
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: apiToken $API_TOKEN" "$USERS_ENDPOINT")
# Use sed instead of head -n -1 for better cross-platform compatibility
USERS=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

# Check if successful
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: API request failed with HTTP code $HTTP_CODE"
    exit 1
fi

if [[ -z "$USERS" ]]; then
    echo "No response from API. Exiting."
    exit 1
fi

# Process users - using a process substitution to avoid subshell variable scope issues
while IFS=$'\t' read -r ID NAME LAST_LOGIN_MS; do
    # Check if LAST_LOGIN_MS is a number
    if [[ "$LAST_LOGIN_MS" =~ ^[0-9]+$ ]]; then
        # Convert ms -> seconds
        LAST_LOGIN_TS=$((LAST_LOGIN_MS / 1000))
    
        if [[ "$LAST_LOGIN_TS" -gt 0 ]]; then
            NOW_TS=$(date +%s)
            DIFF_SEC=$((NOW_TS - LAST_LOGIN_TS))
            DIFF_MONTHS=$((DIFF_SEC / 60 / 60 / 24 / 30))
    
            # Convert timestamp to readable date with better cross-platform handling
            OS_TYPE=$(uname)
            if [[ "$OS_TYPE" == "Darwin" ]]; then
                # macOS
                LAST_LOGIN_DATE=$(date -r "$LAST_LOGIN_TS" "+%Y-%m-%d %H:%M:%S")
            elif [[ "$OS_TYPE" == "Linux" ]]; then
                # Linux
                LAST_LOGIN_DATE=$(date -d "@$LAST_LOGIN_TS" "+%Y-%m-%d %H:%M:%S")
            else
                # Fallback for other Unix-like systems
                # Try Linux style first, then fall back to Perl if that fails
                if date -d "@$LAST_LOGIN_TS" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
                    LAST_LOGIN_DATE=$(date -d "@$LAST_LOGIN_TS" "+%Y-%m-%d %H:%M:%S")
                else
                    # Ultimate fallback to Perl which is highly portable
                    LAST_LOGIN_DATE=$(perl -e "use POSIX qw(strftime); print strftime('%Y-%m-%d %H:%M:%S', localtime($LAST_LOGIN_TS))")
                fi
            fi
    
            if (( DIFF_MONTHS > MONTHS_LIMIT )); then
                # Add to the list of users to be removed from tenant
                USER_LIST+=$'\n'"$ID | $NAME | $LAST_LOGIN_DATE | $DIFF_MONTHS"
                
                # Add user ID to JSON array
                USER_IDS_JSON=$(echo "$USER_IDS_JSON" | jq --arg id "$ID" '. += [$id]')
                
                # Increment the counter
                ((USERS_TO_REMOVE++))
            fi
        fi
    fi
done < <(echo "$USERS" | jq -r '.[] | "\(.id)\t\(.fullName)\t\(.lastLoggedIn)"')

# Display the final list of users to be removed from tenant
echo ""
echo "====== SUMMARY ======"
echo "Found $USERS_TO_REMOVE users to be removed from tenant."
echo ""

if [[ $USERS_TO_REMOVE -gt 0 ]]; then
    echo "$USER_LIST"
    
    echo ""
    echo "Do you want to proceed with removing these users from the tenant? (yes/no)"
    read -r USER_CONFIRM
    if [[ "$USER_CONFIRM" != "yes" ]]; then
        echo "User removal cancelled. No changes were made."
        exit 0
    fi
    echo "Proceeding with removal..."
    
    # Call the DELETE API endpoint
    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Authorization: apiToken $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$USER_IDS_JSON" \
        "$DELETE_ENDPOINT")
    # Use sed instead of head -n -1 for better cross-platform compatibility
    DELETE_RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')
    HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

    # Check if successful (204 No Content or 200 OK)
    if [[ "$HTTP_CODE" == "204" || "$HTTP_CODE" == "200" ]]; then
        echo "User removal from tenant completed successfully."
    else
        echo "Error: User removal failed with HTTP code $HTTP_CODE"
        if [[ -n "$DELETE_RESPONSE" ]]; then
            echo "Response: $DELETE_RESPONSE"
        fi
        exit 1
    fi
else
    echo "No users found that meet the removal criteria (inactive for more than $MONTHS_LIMIT months)."
fi