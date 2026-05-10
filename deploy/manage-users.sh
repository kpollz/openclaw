#!/bin/bash
# =============================================================================
# OpenClaw Multi-User Management Script
# =============================================================================
# Usage: bash manage-users.sh <command> [username]
#
# Commands:
#   list                    List all user instances
#   status [username]       Show status of instance(s)
#   start <username>        Start a specific user instance
#   stop <username>         Stop a specific user instance
#   restart <username>     Restart a specific user instance
#   logs <username>         Show logs for a user instance
#   url <username>          Show connection URL for a user
#   delete <username>       Delete a user instance
#   backup <username>       Backup a user instance
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_DIR="$SCRIPT_DIR/users"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if users directory exists
if [ ! -d "$USERS_DIR" ]; then
    echo -e "${YELLOW}No users directory found${NC}"
    echo "Create a user first with: bash setup-user.sh <username>"
    exit 0
fi

# Get all user directories
get_users() {
    find "$USERS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

# Get user port
get_user_port() {
    local user_dir="$1"
    local env_file="$user_dir/.env"
    if [ -f "$env_file" ]; then
        grep "^OPENCLAW_GATEWAY_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2
    fi
}

# Get user token (truncated)
get_user_token() {
    local user_dir="$1"
    local env_file="$user_dir/.env"
    if [ -f "$env_file" ]; then
        local token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$token" ]; then
            echo "${token:0:16}..."
        fi
    fi
}

# Check if container is running
is_container_running() {
    local username="$1"
    local port=$(get_user_port "$USERS_DIR/$username")
    if [ -n "$port" ]; then
        # Check if port is in use
        if command -v lsof >/dev/null 2>&1; then
            lsof -i ":$port" -sTCP:LISTEN -t >/dev/null 2>&1
        else
            # Fallback: check with netstat or ss
            netstat -an 2>/dev/null | grep -q ":$port.*LISTEN" || \
            ss -ln 2>/dev/null | grep -q ":$port"
        fi
    else
        false
    fi
}

# Command: list
cmd_list() {
    echo "=== OpenClaw User Instances ==="
    echo ""

    local users=$(get_users)
    if [ -z "$users" ]; then
        echo -e "${YELLOW}No user instances found${NC}"
        echo "Create one with: bash setup-user.sh <username>"
        return
    fi

    printf "%-20s %-10s %-10s %-20s\n" "Username" "Port" "Status" "Token"
    printf "%s\n" "--------------------------------------------------------------------------------"

    for user in $users; do
        local user_dir="$USERS_DIR/$user"
        local port=$(get_user_port "$user_dir")
        local token=$(get_user_token "$user_dir")

        if [ -z "$port" ]; then
            port="N/A"
        fi

        if is_container_running "$user"; then
            status="${GREEN}Running${NC}"
        else
            status="${YELLOW}Stopped${NC}"
        fi

        printf "%-20s %-10s %-20s %-20s\n" "$user" "$port" "$status" "$token"
    done

    echo ""
    echo "Total instances: $(echo "$users" | wc -l)"
}

# Command: status
cmd_status() {
    local username="$1"

    if [ -n "$username" ]; then
        # Show status for specific user
        local user_dir="$USERS_DIR/$username"
        if [ ! -d "$user_dir" ]; then
            echo -e "${RED}User not found: $username${NC}"
            exit 1
        fi

        echo "=== Status: $username ==="
        echo "Location: $user_dir"
        echo "Port: $(get_user_port "$user_dir")"

        if is_container_running "$username"; then
            echo -e "Status: ${GREEN}Running${NC}"

            # Show container info if docker compose is available
            if [ -f "$user_dir/docker-compose.yml" ]; then
                echo ""
                cd "$user_dir"
                docker compose ps 2>/dev/null || true
            fi
        else
            echo -e "Status: ${YELLOW}Stopped${NC}"
        fi
    else
        # Show status for all users
        local users=$(get_users)
        for user in $users; do
            cmd_status "$user"
            echo ""
        done
    fi
}

# Command: start
cmd_start() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 start <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    if [ ! -f "$user_dir/docker-compose.yml" ]; then
        echo -e "${RED}docker-compose.yml not found for: $username${NC}"
        exit 1
    fi

    echo "Starting instance: $username..."
    cd "$user_dir"
    docker compose up -d

    echo ""
    if is_container_running "$username"; then
        echo -e "${GREEN}Started successfully${NC}"
        local port=$(get_user_port "$user_dir")
        echo "Web UI: http://localhost:$port"
    else
        echo -e "${YELLOW}Failed to start${NC}"
        echo "Check logs: $0 logs $username"
    fi
}

# Command: stop
cmd_stop() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 stop <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    if [ ! -f "$user_dir/docker-compose.yml" ]; then
        echo -e "${RED}docker-compose.yml not found for: $username${NC}"
        exit 1
    fi

    echo "Stopping instance: $username..."
    cd "$user_dir"
    docker compose down

    echo -e "${GREEN}Stopped${NC}"
}

# Command: restart
cmd_restart() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 restart <username>"
        exit 1
    fi

    cmd_stop "$username"
    sleep 2
    cmd_start "$username"
}

# Command: logs
cmd_logs() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 logs <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    cd "$user_dir"
    docker compose logs -f "${2:-}"
}

# Command: url
cmd_url() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 url <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    local port=$(get_user_port "$user_dir")
    local token=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$user_dir/.env" 2>/dev/null | cut -d'=' -f2)

    echo "=== Connection Info: $username ==="
    echo ""
    echo "Web UI:"
    echo -e "  URL:    ${GREEN}http://localhost:$port${NC}"
    echo -e "  Token:  ${CYAN}$token${NC}"
    echo ""
    echo "Use this token to authenticate on the web UI."
}

# Command: delete
cmd_delete() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 delete <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    # Stop if running
    if is_container_running "$username"; then
        echo "Stopping instance..."
        cmd_stop "$username"
    fi

    echo -e "${YELLOW}This will delete all data for: $username${NC}"
    echo "Location: $user_dir"
    read -p "Are you sure? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$user_dir"
        echo -e "${GREEN}Deleted: $username${NC}"
    else
        echo "Aborted"
    fi
}

# Command: backup
cmd_backup() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 backup <username>"
        exit 1
    fi

    local user_dir="$USERS_DIR/$username"
    if [ ! -d "$user_dir" ]; then
        echo -e "${RED}User not found: $username${NC}"
        exit 1
    fi

    local backup_dir="$SCRIPT_DIR/backups"
    mkdir -p "$backup_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${username}_${timestamp}.tar.gz"

    echo "Creating backup: $backup_file"

    # Stop if running
    if is_container_running "$username"; then
        echo "Stopping instance for backup..."
        cmd_stop "$username"
    fi

    # Create backup
    tar -czf "$backup_file" -C "$user_dir" .

    echo -e "${GREEN}Backup created: $backup_file${NC}"
    echo "Size: $(du -h "$backup_file" | cut -f1)"
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 <command> [username]

Commands:
  list                    List all user instances
  status [username]       Show status of instance(s)
  start <username>        Start a specific user instance
  stop <username>         Stop a specific user instance
  restart <username>      Restart a specific user instance
  logs <username>         Show logs for a user instance
  url <username>          Show connection URL for a user
  delete <username>       Delete a user instance
  backup <username>       Backup a user instance

Examples:
  $0 list                              # List all users
  $0 start john                        # Start john's instance
  $0 logs john                         # Show john's logs
  $0 url john                          # Show john's connection URL
  $0 backup john                       # Backup john's data
EOF
}

# Main
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    list)
        cmd_list
        ;;
    status)
        cmd_status "$@"
        ;;
    start)
        cmd_start "$@"
        ;;
    stop)
        cmd_stop "$@"
        ;;
    restart)
        cmd_restart "$@"
        ;;
    logs)
        cmd_logs "$@"
        ;;
    url)
        cmd_url "$@"
        ;;
    delete)
        cmd_delete "$@"
        ;;
    backup)
        cmd_backup "$@"
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
