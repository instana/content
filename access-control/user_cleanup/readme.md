# User Cleanup Script

## Overview

This script identifies and removes inactive users from your tenant based on their last login time. It provides a safe, interactive way to clean up user accounts that haven't been accessed for a specified period.

## What This Script Does

1. Fetches all users from the API
2. Calculates inactivity period (in months) based on last login time
3. Lists users inactive for more than the specified threshold
4. Displays a summary and prompts for confirmation
5. Removes confirmed users via API (irreversible operation)

## ⚠️ Important Warning

**This operation is IRREVERSIBLE.** Once users are deleted, they cannot be recovered. Always:
- Test with a large MONTHS_LIMIT first (e.g., 24 months) to see fewer users
- Carefully review the list of users before confirming deletion
- Consider backing up user data before running in production
- Start with a dry run to understand the impact

## Platform Support

This is a **Bash script** designed for Unix-like systems:

- ✅ **macOS** - Fully supported
- ✅ **Linux** - Fully supported  
- ⚠️ **Windows** - Requires WSL (Windows Subsystem for Linux) or Git Bash

**Windows users**: Install WSL with `wsl --install` in PowerShell, then run the script in the WSL terminal.

## Prerequisites

Before running this script, ensure you have:

- **Bash 4.0 or higher**
- **jq** (JSON processor)
  - macOS: `brew install jq`
  - Linux: `sudo apt-get install jq` or `sudo yum install jq`
- **curl** (usually pre-installed)
- **API Token with "User Management" permission**

## How to Run the Script

### 1. Direct Command Line Usage

The simplest way to run the script is by providing the required arguments:

```bash
./cleanup_users.sh https://your-app-url.com/api MONTHS_LIMIT
```

This will prompt you for the API_TOKEN interactively (recommended for security).

**Example**: Remove users inactive for 6+ months
```bash
./cleanup_users.sh https://api.example.com 6
```

### 2. With All Parameters

You can provide all parameters including the API_TOKEN (though this is less secure):

```bash
./cleanup_users.sh https://your-app-url.com/api MONTHS_LIMIT your-api-token
```

⚠️ **Security Warning**: This method exposes your token in shell history and process lists.

### 3. Using Environment Variables (Recommended)

For better security, use environment variables for sensitive information:

```bash
# Set the API_TOKEN environment variable
export API_TOKEN="your-api-token"

# Run with just the required arguments
./cleanup_users.sh https://api.example.com 6
```

### 4. Using an Environment File

Create a `.env` file in the same directory as the script:

```bash
# Create the .env file
cat > .env << 'EOF'
export API_TOKEN="your-api-token"
EOF

# Set appropriate permissions (readable only by the owner)
chmod 600 .env

# Source the environment file and run the script
source .env
./cleanup_users.sh https://api.example.com 6
```

## Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `API_BASE_URL` | Yes | Base URL of your API (with protocol) | `https://api.example.com` |
| `MONTHS_LIMIT` | Yes | Inactivity threshold in months | `6` |
| `API_TOKEN` | Yes | API authentication token | Provide via env var or prompt |

## Script Behavior

### What Gets Deleted
- Users whose last login was more than `MONTHS_LIMIT` months ago
- Users are identified by their `lastLoggedIn` timestamp
- The script will show you exactly which users will be removed before deletion

### Confirmation Required
The script will:
1. Display a table of users to be removed with their details
2. Show the total count
3. Ask you to type "yes" to confirm deletion
4. Only proceed if you explicitly confirm

## Security Best Practices

- **Never** pass API_TOKEN as a command-line argument in production environments
- Keep the `.env` file out of version control (add to `.gitignore`)
- Use appropriate file permissions: `chmod 600 .env`
- Consider using a secrets management solution for production environments
- Rotate API tokens regularly
- Always use HTTPS endpoints (not HTTP)
- Test the script in a non-production environment first

## Troubleshooting

### Error: "jq is not installed"
**Solution**: Install jq using your package manager
```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt-get install jq

# Linux (RHEL/CentOS)
sudo yum install jq
```

### Error: "API request failed with HTTP code 401"
**Cause**: Authentication failure

**Solutions**:
- Verify your API_TOKEN is correct and not expired
- Ensure the token is properly set in the environment

### Error: "API request failed with HTTP code 403"
**Cause**: Authorisation failure

**Solutions**:
- Check if the token has the necessary permissions
- Ensure the token is properly set in the environment

### Error: "API request failed with HTTP code 404"
**Cause**: Endpoint not found

**Solutions**:
- Verify the API_BASE_URL is correct
- Ensure the URL includes the protocol (http:// or https://)
- Check if the API endpoints `/settings/users` and `/settings/users/delete` exist

### Script runs but shows "No users found"
**This is normal if**:
- All users are active within the threshold period
- No users meet the inactivity criteria

**To verify**:
- Try with a smaller MONTHS_LIMIT value to capture more recently inactive users
- Check the API response manually using curl

### Permission denied when running script
**Solution**: Make the script executable
```bash
chmod +x cleanup_users.sh
```

## Example Workflow

```bash
# 1. Set up environment
export API_TOKEN="your-secure-token-here"

# 2. Make script executable (first time only)
chmod +x cleanup_users.sh

# 3. Run with 6-month threshold
./cleanup_users.sh https://api.example.com 6

# 4. Review the output
# The script will show:
# - Total users fetched
# - List of users to be removed
# - Their last login dates
# - Months of inactivity

# 5. Confirm or cancel
# Type "yes" to proceed or anything else to cancel

# 6. Verify results
# The script will confirm successful deletion
```

## What the Output Looks Like

```
Fetching users...
Successfully fetched users

====== SUMMARY ======
Found 3 users to be removed from tenant.

USERS TO BE REMOVED FROM TENANT (Inactive for more than 6 months):
--------------------------------------------------------------
ID | Full Name | Last Login Date | Months Inactive
--------------------------------------------------------------
user123 | John Doe | 2023-01-15 10:30:00 | 8
user456 | Jane Smith | 2023-02-20 14:45:00 | 7
user789 | Bob Johnson | 2022-12-01 09:15:00 | 10

Do you want to proceed with removing these users from the tenant? (yes/no)
```

## Notes

- The script uses a 30-day approximation for month calculations
- Users with `lastLoggedIn = 0` or `null` are intentionally excluded
- The script includes cross-platform date handling for macOS and Linux
- HTTP status codes are validated for both GET and DELETE operations

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Verify all prerequisites are installed
3. Test with a lower MONTHS_LIMIT to see if any users are found
4. Check API endpoint availability and authentication
5. Check if the API Token has right permission of 'User Management'