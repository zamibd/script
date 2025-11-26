#!/bin/bash

# Go Uninstallation Script for Ubuntu Server
# This script removes Go installation and cleans up environment configurations

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check execution context and set up variables
IS_ROOT=false
SUDO_CMD=""
USER_HOME=""

if [[ $EUID -eq 0 ]]; then
    IS_ROOT=true
    print_warning "Running as root user."
    
    # Determine the actual user if running via sudo
    if [[ -n "$SUDO_USER" ]]; then
        ACTUAL_USER="$SUDO_USER"
        USER_HOME="/home/$SUDO_USER"
        print_info "Detected original user: $ACTUAL_USER"
    else
        ACTUAL_USER="root"
        USER_HOME="/root"
        print_info "Running directly as root user."
    fi
else
    ACTUAL_USER="$USER"
    USER_HOME="$HOME"
    SUDO_CMD="sudo"
    print_info "Running as regular user: $ACTUAL_USER"
fi

print_info "User home directory: $USER_HOME"

# Function to backup files before removal
backup_file() {
    local file="$1"
    local backup_dir="$USER_HOME/.go_uninstall_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        cp "$file" "$backup_dir/$(basename $file).backup"
        print_info "Backed up $file to $backup_dir"
        echo "$backup_dir" > /tmp/go_backup_location
    fi
}

# Function to remove Go environment variables from files
remove_go_env() {
    local file="$1"
    local temp_file="/tmp/go_env_cleanup_$$"
    
    if [[ -f "$file" ]]; then
        print_info "Cleaning Go environment variables from $file"
        
        # Create backup before modification
        backup_file "$file"
        
        # Remove Go environment section
        awk '
        /^# Go environment$/ { in_go_section = 1; next }
        in_go_section && /^$/ { in_go_section = 0; next }
        in_go_section && /^export/ { next }
        !in_go_section
        ' "$file" > "$temp_file"
        
        # Replace original file
        mv "$temp_file" "$file"
        
        # Set proper ownership if running as root
        if [[ $IS_ROOT == true && "$ACTUAL_USER" != "root" ]]; then
            chown "$ACTUAL_USER:$ACTUAL_USER" "$file"
        fi
        
        print_success "Cleaned $file"
    fi
}

# Check if Go is installed
print_info "Checking Go installation..."
if ! command -v go &> /dev/null; then
    print_warning "Go is not currently installed or not in PATH."
    print_info "Checking for Go installation directory..."
    
    if [[ -d "/usr/local/go" ]]; then
        print_warning "Found Go installation directory at /usr/local/go"
    else
        print_info "No Go installation directory found."
        print_info "Proceeding with environment cleanup only..."
    fi
else
    GO_VERSION=$(go version)
    print_info "Found Go installation: $GO_VERSION"
    GO_ROOT=$(go env GOROOT 2>/dev/null || echo "/usr/local/go")
    GO_PATH=$(go env GOPATH 2>/dev/null || echo "$USER_HOME/go")
    print_info "GOROOT: $GO_ROOT"
    print_info "GOPATH: $GO_PATH"
fi

# Automatic uninstallation (no user confirmation)
echo
print_warning "Automatically removing Go and cleaning up all related configurations."
print_info "The following will be removed/cleaned:"
echo "  - Go installation directory (/usr/local/go)"
echo "  - Go workspace directory ($USER_HOME/go)"
echo "  - Go environment variables from shell configuration files"
echo "  - Go tools and binaries"
echo "  - Go build cache and module cache"
echo
print_info "Configuration files will be backed up before modification."
print_info "Starting automatic uninstallation..."
echo

# Stop any running Go processes
print_info "Checking for running Go processes..."
GO_PROCESSES=$(pgrep -f "go " || true)
if [[ -n "$GO_PROCESSES" ]]; then
    print_warning "Found running Go processes. Attempting to stop them..."
    pkill -f "go " || true
    sleep 2
    print_info "Go processes stopped."
fi

# Remove Go installation directory
if [[ -d "/usr/local/go" ]]; then
    print_info "Removing Go installation directory..."
    $SUDO_CMD rm -rf /usr/local/go
    print_success "Removed /usr/local/go"
else
    print_info "Go installation directory not found at /usr/local/go"
fi

# Automatically remove Go workspace
if [[ -d "$USER_HOME/go" ]]; then
    print_info "Removing Go workspace at: $USER_HOME/go"
    rm -rf "$USER_HOME/go"
    print_success "Removed Go workspace: $USER_HOME/go"
else
    print_info "No Go workspace found at $USER_HOME/go"
fi

# Clean environment variables from shell configuration files
print_info "Cleaning Go environment variables from shell configuration files..."

# Clean .bashrc
if [[ -f "$USER_HOME/.bashrc" ]]; then
    remove_go_env "$USER_HOME/.bashrc"
fi

# Clean .profile
if [[ -f "$USER_HOME/.profile" ]]; then
    remove_go_env "$USER_HOME/.profile"
fi

# Clean .zshrc (if exists)
if [[ -f "$USER_HOME/.zshrc" ]]; then
    remove_go_env "$USER_HOME/.zshrc"
fi

# Clean .bash_profile (if exists)
if [[ -f "$USER_HOME/.bash_profile" ]]; then
    remove_go_env "$USER_HOME/.bash_profile"
fi

# Remove Go binaries from common locations
print_info "Cleaning Go binaries from system PATH..."

# Remove from /usr/local/bin if they're symlinks to Go installation
for binary in go gofmt godoc; do
    if [[ -L "/usr/local/bin/$binary" ]]; then
        $SUDO_CMD rm -f "/usr/local/bin/$binary"
        print_info "Removed symlink: /usr/local/bin/$binary"
    fi
done

# Clean up any Go-related packages installed via package manager
print_info "Checking for Go packages installed via package manager..."
if dpkg -l | grep -q golang; then
    print_warning "Found Go packages installed via apt. Removing them..."
    $SUDO_CMD apt-get remove -y golang-go golang-doc golang-src golang-misc 2>/dev/null || true
    $SUDO_CMD apt-get autoremove -y 2>/dev/null || true
    print_success "Removed Go packages from package manager"
fi

# Remove Go module cache (automatic removal)
if [[ -d "$USER_HOME/.cache/go-build" ]]; then
    print_info "Removing Go build cache..."
    rm -rf "$USER_HOME/.cache/go-build"
    print_success "Removed Go build cache"
fi

# Remove Go module proxy cache (automatic removal)
if [[ -d "$USER_HOME/go/pkg/mod" ]]; then
    print_info "Removing Go module cache..."
    rm -rf "$USER_HOME/go/pkg/mod"
    print_success "Removed Go module cache"
fi

# Verify uninstallation
print_info "Verifying Go removal..."
if command -v go &> /dev/null; then
    GO_LOCATION=$(which go)
    print_warning "Go binary still found at: $GO_LOCATION"
    print_warning "You may need to restart your terminal or manually remove this binary."
else
    print_success "Go binary successfully removed from PATH"
fi

# Check if installation directory still exists
if [[ -d "/usr/local/go" ]]; then
    print_warning "Go installation directory still exists at /usr/local/go"
else
    print_success "Go installation directory successfully removed"
fi

# Display backup information
if [[ -f "/tmp/go_backup_location" ]]; then
    BACKUP_DIR=$(cat /tmp/go_backup_location)
    print_info "Configuration file backups are stored in: $BACKUP_DIR"
    rm -f /tmp/go_backup_location
fi

print_success "Go uninstallation completed!"
echo
print_info "Uninstallation Summary:"
echo "  ✓ Go installation directory removed"
echo "  ✓ Environment variables cleaned from shell configuration files"
echo "  ✓ System binaries and symlinks removed"
echo "  ✓ Package manager installations cleaned up"
echo "  ✓ Build cache removed"
echo
print_warning "Please restart your terminal or run 'source ~/.bashrc' to update your environment."
print_info "If you reinstall Go in the future, you may need to reconfigure your projects."
echo
print_info "Uninstallation completed successfully! 🗑️"