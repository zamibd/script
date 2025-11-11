#!/bin/bash

# Function to check for root privileges
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root or with sudo."
        exit 1
    fi
}

# Main uninstallation function
uninstall_nginx() {
    echo "--- Starting Nginx uninstallation process ---"

    # 1. Stop Nginx service
    echo "1. Stopping Nginx service..."
    systemctl stop nginx 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Nginx service stopped successfully."
    else
        echo "Nginx service was not running or failed to stop (continuing)."
    fi

    # 2. Purge all Nginx packages and configuration files
    echo "2. Purging Nginx packages and configuration files..."
    apt-get purge -y nginx nginx-common nginx-full nginx-core 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Nginx packages and configuration files purged successfully."
    else
        echo "Failed to purge Nginx packages. Please check apt logs."
    fi

    # 3. Remove automatically installed, no-longer-needed dependencies
    echo "3. Removing orphaned dependencies..."
    apt-get autoremove -y

    # 4. Remove remaining directories (logs, cache, etc.)
    echo "4. Removing remaining directories: /etc/nginx, /var/log/nginx, /var/cache/nginx..."
    rm -rf /etc/nginx
    rm -rf /var/log/nginx
    rm -rf /var/cache/nginx

    echo "--- Nginx uninstallation complete ---"
}

# Execute script
check_root
uninstall_nginx
