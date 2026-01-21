#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# maintenance.sh - System maintenance service
# Requirements: Bash 4.0+, CentOS/RHEL system
# Description: Automated system updates, backups, and website monitoring
# -----------------------------------------------------------------------------

# 1. Compatibility & Portability Check
if (( BASH_VERSINFO[0] < 4 )); then
    printf "Error: This script requires Bash 4.0 or higher.\n" >&2
    exit 1
fi

# 2. Security & Environment Setup
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Secure PATH with absolute paths
readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 3. Constants & Globals
readonly SCRIPT_NAME="${0##*/}"
readonly PID_FILE="/var/run/maintenance.pid"
readonly LOG_FILE="/var/log/maintenance.log"
readonly TMP_DIR="${TMPDIR:-/tmp}"

# Default Flags
VERBOSE=0
DEBUG=0

# Temporary files for cleanup
TEMP_FILES=()

# 4. Error Handling & Cleanup
cleanup() {
    local temp_file
    for temp_file in "${TEMP_FILES[@]}"; do
        if [[ -f "$temp_file" ]]; then
            if (( DEBUG )); then
                printf "[DEBUG] Cleaning up temp file: %s\n" "$temp_file" >&2
            fi
            rm -f "$temp_file"
        fi
    done
    TEMP_FILES=()
}
trap cleanup EXIT

err_report() {
    local line=$1
    local cmd=$2
    printf "Error in %s at line %d: '%s' failed with exit status %d\n" \
        "$SCRIPT_NAME" "$line" "$cmd" "$?" >&2
}
trap 'err_report $LINENO "$BASH_COMMAND"' ERR

# 5. Logging Helpers
log_debug() {
    if (( DEBUG )); then
        printf "[DEBUG] %s\n" "$*" >&2
    fi
}

log_verbose() {
    if (( VERBOSE )); then
        printf "[INFO] %s\n" "$*" >&2
    fi
}

log_error() {
    printf "[ERROR] %s\n" "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# 6. Usage Information
usage() {
    cat <<EOF >&2
Usage: $SCRIPT_NAME [OPTIONS] {start|stop|status|restart}

Commands:
  start       Start the maintenance service
  stop        Stop the maintenance service
  status      Check service status
  restart     Restart the maintenance service

Options:
  -v, --verbose    Enable verbose logging
  -d, --debug      Enable debug logging (implies verbose)
  -h, --help       Show this help message

Configuration:
  MYSQL_USER       MySQL username (required for backup)
  MYSQL_PASSWD     MySQL password (required for backup)
  MYSQL_DB         MySQL database name (required for backup)
  BLOG_DIR         Blog directory path (default: /home/cienciahacker/blog)
  SITE_DIR         Site directory path (default: /home/cienciahacker/site)
  BACKUP_DIR       Backup directory (default: /home/cienciahacker/backup)

Example:
  export MYSQL_USER="user"
  export MYSQL_PASSWD="password"
  export MYSQL_DB="database"
  sudo $SCRIPT_NAME -v start
EOF
}

# 7. Argument Parsing
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--debug)
                DEBUG=1
                VERBOSE=1
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if (( $# == 0 )); then
        usage
        die "Error: No command specified"
    fi
}

# 8. Root Privilege Check
check_root() {
    local uid
    uid=$(id -u)
    if (( uid != 0 )); then
        die "Run with sudo or as root"
    fi
    log_verbose "Root privilege verified"
}

# 9. Log Entry Function
log_to_file() {
    local message=$1
    local timestamp
    # Prevent log injection by using ISO 8601 format
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S%z")
    # Validate log file is writable
    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
        printf "[%s] %s\n" "$timestamp" "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 10. System Update Function
att() {
    log_verbose "Checking for system updates..."
    
    if ! command -v yum >/dev/null 2>&1; then
        log_error "yum command not found. This script requires CentOS/RHEL."
        return 1
    fi

    if yum update -y -q; then
        log_to_file "System update completed successfully"
        log_verbose "System update completed"
    else
        log_to_file "System update failed"
        log_error "System update failed"
        return 1
    fi
}

# 11. Backup Function with Security Hardening
backup() {
    log_verbose "Starting backup process..."

    # Configuration from environment variables
    local mysql_user="${MYSQL_USER:-}"
    local mysql_passwd="${MYSQL_PASSWD:-}"
    local wp_db="${MYSQL_DB:-}"
    local blog_dir="${BLOG_DIR:-/home/cienciahacker/blog}"
    local site_dir="${SITE_DIR:-/home/cienciahacker/site}"
    local backup_dir="${BACKUP_DIR:-/home/cienciahacker/backup}"

    # Validate required credentials
    if [[ -z "$mysql_user" ]] || [[ -z "$mysql_passwd" ]] || [[ -z "$wp_db" ]]; then
        die "Backup requires MYSQL_USER, MYSQL_PASSWD, and MYSQL_DB environment variables"
    fi

    # Validate source directories exist
    if [[ ! -d "$blog_dir" ]]; then
        die "Blog directory not found: $blog_dir"
    fi
    if [[ ! -d "$site_dir" ]]; then
        die "Site directory not found: $site_dir"
    fi

    # Create backup directory if needed
    if ! mkdir -p "$backup_dir"; then
        die "Failed to create backup directory: $backup_dir"
    fi

    # Generate timestamp for backup filename
    local timestamp
    timestamp=$(date +"%Y-%m-%d")
    local backup_file="bkp_ch_${timestamp}.tar.gz"
    local backup_path="${backup_dir}/${backup_file}"

    # Check if backup already exists
    if [[ -f "$backup_path" ]]; then
        log_verbose "Backup already exists for today: $backup_file"
        return 0
    fi

    # Create secure temporary directory
    local temp_base_dir
    temp_base_dir=$(umask 077 && mktemp -d "${TMP_DIR}/${SCRIPT_NAME}.XXXXXX") || \
        die "Failed to create temporary directory"
    TEMP_FILES+=("$temp_base_dir")

    # Use subdirectories for security (prevent symlink attacks)
    local blog_tar="${temp_base_dir}/blog_dir.tar.gz"
    local site_tar="${temp_base_dir}/site_dir.tar.gz"
    local sql_dump="${temp_base_dir}/wp_db.sql"

    # Create blog backup
    log_verbose "Backing up blog directory: $blog_dir"
    if ! tar -zcf "$blog_tar" -- "$blog_dir"; then
        die "Failed to create blog backup"
    fi

    # Create site backup
    log_verbose "Backing up site directory: $site_dir"
    if ! tar -zcf "$site_tar" -- "$site_dir"; then
        die "Failed to create site backup"
    fi

    # Create MySQL dump (prevent command injection)
    log_verbose "Creating MySQL database dump..."
    if ! mysqldump -u"$mysql_user" -p"$mysql_passwd" -- "$wp_db" > "$sql_dump" 2>/dev/null; then
        die "Failed to create MySQL dump"
    fi
    chmod 600 "$sql_dump"

    # Combine all backups
    log_verbose "Combining backup files..."
    if ! tar -zcf "${temp_base_dir}/${backup_file}" -C "$temp_base_dir" \
        blog_dir.tar.gz site_dir.tar.gz wp_db.sql; then
        die "Failed to combine backup files"
    fi

    # Move to backup destination
    log_verbose "Moving backup to: $backup_dir"
    if ! mv "${temp_base_dir}/${backup_file}" "$backup_path"; then
        die "Failed to move backup to destination"
    fi

    # Set secure permissions on backup file
    chmod 600 "$backup_path"

    log_to_file "Backup completed: ${backup_file}"
    log_verbose "Backup completed successfully: $backup_file"
}

# 12. Site Status Monitoring Function
site_status() {
    log_debug "Starting site status monitoring..."

    # Error message to detect
    local message="Eita giovana"

    # Pages to monitor (use array for safety)
    local pages=(
        "https://cienciahacker.ch"
        "https://blog.cienciahacker.ch"
    )

    log_debug "Monitoring ${#pages[@]} pages"

    while :; do
        for page in "${pages[@]}"; do
            log_debug "Checking: $page"

            # Retrieve HTML with timeout (5 seconds)
            local html
            html=$(curl -s --max-time 5 --fail "$page" 2>/dev/null || true)

            # Check for error message in HTML
            if [[ "$html" == *"$message"* ]]; then
                log_verbose "Page unavailable detected: $page"
                
                # Restart services
                log_verbose "Restarting mariadb service..."
                if systemctl restart mariadb 2>/dev/null; then
                    log_to_file "mariadb restarted due to: $page"
                else
                    log_to_file "Failed to restart mariadb"
                fi

                log_verbose "Restarting httpd service..."
                if systemctl restart httpd 2>/dev/null; then
                    log_to_file "httpd restarted due to: $page"
                else
                    log_to_file "Failed to restart httpd"
                fi

                log_to_file "Services restarted due to: $page unavailable"
            else
                log_debug "Page OK: $page"
            fi
        done

        # Sleep for 5 minutes (300 seconds)
        log_debug "Sleeping for 300 seconds..."
        sleep 300
    done
}

# 13. Start Service Function
start() {
    log_verbose "Starting maintenance service..."

    # Check if already running
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "0")
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            die "Service is already running (PID: $existing_pid)"
        fi
        # Stale PID file, remove it
        rm -f "$PID_FILE"
    fi

    # Create PID file directory if needed
    local pid_dir
    pid_dir=$(dirname "$PID_FILE")
    if [[ ! -d "$pid_dir" ]]; then
        mkdir -p "$pid_dir" || die "Failed to create PID directory: $pid_dir"
    fi

    # Start monitoring in background
    site_status &
    local monitor_pid=$!
    echo "$monitor_pid" > "$PID_FILE"
    log_verbose "Monitor started with PID: $monitor_pid"

    # Start maintenance loop in background
    (
        while :; do
            log_verbose "Running scheduled tasks..."
            att
            backup
            log_verbose "Next run in 3 days..."
            sleep 259200  # 3 days
        done
    ) &
    local maintenance_pid=$!
    echo "$maintenance_pid" >> "$PID_FILE"
    log_verbose "Maintenance scheduler started with PID: $maintenance_pid"

    printf "[+] Service started\n"
}

# 14. Stop Service Function
stop() {
    log_verbose "Stopping maintenance service..."

    if [[ ! -f "$PID_FILE" ]]; then
        printf "[+] Service is not running\n"
        return 0
    fi

    # Read PIDs safely
    local pids=()
    while IFS= read -r pid; do
        # Validate PID is numeric
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            pids+=("$pid")
        fi
    done < "$PID_FILE"

    if (( ${#pids[@]} == 0 )); then
        printf "[+] No running processes found\n"
        rm -f "$PID_FILE"
        return 0
    fi

    # Terminate processes
    local stopped=0
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_verbose "Stopping PID: $pid"
            kill "$pid" 2>/dev/null || true
            ((stopped++))
        else
            log_debug "PID $pid already dead"
        fi
    done

    # Wait for graceful termination
    sleep 2

    # Force kill if still running
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_debug "Force killing PID: $pid"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    rm -f "$PID_FILE"
    printf "[+] Service stopped (%d processes)\n" "$stopped"
}

# 15. Status Function
status() {
    if [[ -f "$PID_FILE" ]]; then
        local running=0
        local pids=()
        while IFS= read -r pid; do
            if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                pids+=("$pid")
                ((running++))
            fi
        done < "$PID_FILE"

        if (( running > 0 )); then
            printf "[+] Service is running (%d process(es)): %s\n" \
                "$running" "${pids[*]}"
        else
            printf "[+] Service is not running (stale PID file)\n"
            rm -f "$PID_FILE"
        fi
    else
        printf "[+] Service is not running\n"
    fi
}

# 16. Main Entry Point
main() {
    parse_args "$@"

    local command="${1:-}"
    shift || true

    case "$command" in
        start)
            start
            ;;
        stop)
            stop
            ;;
        status)
            status
            ;;
        restart)
            stop
            sleep 1
            start
            ;;
        *)
            usage
            die "Invalid command: $command"
            ;;
    esac
}

# 17. Execute Main
main "$@"
