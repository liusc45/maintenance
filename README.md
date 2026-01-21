# Maintenance

Automated system maintenance script for CentOS/RHEL servers. Provides secure backup, system updates, and website monitoring with robust error handling and security hardening.

## Features

- **Secure System Updates**: Automated yum updates with logging
- **Comprehensive Backups**: 
  - Web server directories (blog, site)
  - MySQL database dumps
  - Encrypted tar archives with secure permissions
- **Website Monitoring**: Continuous uptime monitoring with automatic service restart
- **Security Hardening**: 
  - No hardcoded credentials
  - Secure temporary file handling
  - Command injection prevention
  - Proper signal handling and cleanup

## Requirements

- **Bash 4.0+** (enforced at runtime)
- **CentOS/RHEL** (uses yum package manager)
- **Root privileges** (required for system updates and service management)
- **MySQL credentials** (provided via environment variables)

## Installation

1. Clone or download the script:
```bash
wget https://raw.githubusercontent.com/fnk0c/maintenance/main/maintenance.sh
chmod +x maintenance.sh
```

2. Move to system location (optional):
```bash
sudo mv maintenance.sh /usr/local/bin/maintenance
```

## Configuration

Set environment variables for backup functionality:

```bash
export MYSQL_USER="your_mysql_user"
export MYSQL_PASSWD="your_mysql_password"
export MYSQL_DB="your_database_name"
export BLOG_DIR="/home/cienciahacker/blog"
export SITE_DIR="/home/cienciahacker/site"
export BACKUP_DIR="/home/cienciahacker/backup"
```

## Usage

### Command Line Options

```bash
./maintenance.sh [OPTIONS] {start|stop|status|restart}
```

**Commands:**
- `start` - Start the maintenance service
- `stop` - Stop the maintenance service  
- `status` - Check service status
- `restart` - Restart the maintenance service

**Options:**
- `-v, --verbose` - Enable verbose logging
- `-d, --debug` - Enable debug logging (implies verbose)
- `-h, --help` - Show help message

### Examples

**Start with verbose logging:**
```bash
sudo ./maintenance.sh -v start
```

**Check status:**
```bash
sudo ./maintenance.sh status
```

**Stop service:**
```bash
sudo ./maintenance.sh stop
```

**Restart with debug:**
```bash
sudo ./maintenance.sh -d restart
```

## Security Features

### 1. Secure Credentials
- **No hardcoded passwords** - All credentials via environment variables
- **Command injection prevention** - Proper quoting and validation
- **Secure file permissions** - 0600 for sensitive files

### 2. Temporary File Handling
- Uses `mktemp` with secure permissions (umask 077)
- Automatic cleanup on exit (normal, error, or signal)
- Prevents symlink attacks with dedicated directories

### 3. Process Management
- PID file validation before kill operations
- Graceful shutdown with fallback to force kill
- Stale PID file detection and cleanup

### 4. Logging Security
- ISO 8601 timestamps prevent log injection
- Logs written to `/var/log/maintenance.log`
- Debug/verbose output to stderr only

### 5. Error Handling
- `set -Eeuo pipefail` for strict error checking
- Error trap with line number and command context
- Idempotent cleanup logic

## Service Integration

### Systemd (CentOS/RHEL)

Create `/etc/systemd/system/maintenance.service`:

```ini
[Unit]
Description=Maintenance script to backup, update system and retrieve website status
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/maintenance start
ExecStop=/usr/local/bin/maintenance stop
Restart=on-failure
PIDFile=/var/run/maintenance.pid
Environment="MYSQL_USER=your_user"
Environment="MYSQL_PASSWD=your_password"
Environment="MYSQL_DB=your_db"

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable maintenance
sudo systemctl start maintenance
```

### Init.d (Legacy Systems)

```bash
sudo mv maintenance.sh /etc/init.d/maintenance
sudo chmod 755 /etc/init.d/maintenance
sudo chkconfig maintenance on
sudo service maintenance start
```

## Operations

### Backup Process
1. Validates MySQL credentials and directories
2. Creates blog and site tar archives
3. Generates MySQL database dump
4. Combines into single encrypted archive
5. Moves to backup directory with secure permissions
6. Logs completion timestamp

### System Updates
- Runs `yum update -y -q` automatically
- Logs success/failure to maintenance log
- Runs every 3 days (259200 seconds)

### Website Monitoring
- Monitors configured URLs every 5 minutes
- Detects specific error message ("Eita giovana")
- Automatically restarts mariadb and httpd services on failure
- Logs all restart events

## File Locations

- **PID File**: `/var/run/maintenance.pid`
- **Log File**: `/var/log/maintenance.log`
- **Backup Directory**: `/home/cienciahacker/backup` (configurable)
- **Temp Directory**: System temp (configurable via TMPDIR)

## Troubleshooting

### Service won't start
```bash
# Check if already running
sudo ./maintenance.sh status

# Check PID file
sudo cat /var/run/maintenance.pid
sudo ps aux | grep maintenance

# Force stop if needed
sudo ./maintenance.sh stop
```

### Backup fails
```bash
# Verify environment variables
echo $MYSQL_USER $MYSQL_PASSWD $MYSQL_DB

# Check directory permissions
sudo ls -la /home/cienciahacker/

# Test MySQL connection manually
mysql -u$MYSQL_USER -p$MYSQL_PASSWD -e "SHOW DATABASES;"
```

### Monitoring not working
```bash
# Check logs
sudo tail -f /var/log/maintenance.log

# Test curl manually
curl -s --max-time 5 https://cienciahacker.ch
```

## Security Best Practices

1. **Never commit credentials** - Use environment variables or secure vault
2. **Restrict backup directory** - Set proper ownership and permissions
3. **Monitor logs** - Regular review of `/var/log/maintenance.log`
4. **Update regularly** - Keep script updated with latest security fixes
5. **Test restores** - Regularly verify backup integrity

## License

GPLv2 - See original repository for details

## Support

For issues or contributions, visit: https://github.com/fnk0c/maintenance
