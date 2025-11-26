#!/bin/bash

# Go Installation Script for Ubuntu Server (Optimized for Ubuntu 24.04)
# This script automatically downloads and installs the latest version of Go

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

# Check Ubuntu version
print_info "Checking Ubuntu version..."
if ! command -v lsb_release &> /dev/null; then
    $SUDO_CMD apt update && $SUDO_CMD apt install -y lsb-release
fi

UBUNTU_VERSION=$(lsb_release -rs)
print_info "Detected Ubuntu version: $UBUNTU_VERSION"

# Update system packages
print_info "Updating system packages..."
$SUDO_CMD apt update && $SUDO_CMD apt upgrade -y

# Install required dependencies
print_info "Installing required dependencies..."
$SUDO_CMD apt install -y curl wget tar git build-essential

# Get the latest Go version
print_info "Fetching latest Go version information..."

# Function to get Go version with multiple fallback methods
get_latest_go_version() {
    local version=""
    
    # Method 1: Try the new go.dev API endpoint
    print_info "Trying go.dev API..."
    version=$(curl -s -L "https://go.dev/VERSION?m=text" 2>/dev/null | head -n1 | tr -d '\r\n' || echo "")
    
    # Check if we got a valid version (should start with "go")
    if [[ "$version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$version"
        return 0
    fi
    
    # Method 2: Try the original golang.org endpoint
    print_info "Trying golang.org API..."
    version=$(curl -s -L "https://golang.org/VERSION?m=text" 2>/dev/null | head -n1 | tr -d '\r\n' || echo "")
    
    if [[ "$version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$version"
        return 0
    fi
    
    # Method 3: Parse from Go releases page
    print_info "Trying GitHub releases API..."
    version=$(curl -s "https://api.github.com/repos/golang/go/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | grep -o 'go[0-9][^"]*' || echo "")
    
    if [[ "$version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$version"
        return 0
    fi
    
    # Method 4: Parse from Go download page
    print_info "Trying Go download page..."
    version=$(curl -s "https://go.dev/dl/" 2>/dev/null | grep -o 'go[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | head -n1 || echo "")
    
    if [[ "$version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$version"
        return 0
    fi
    
    # If all methods fail, return empty
    echo ""
    return 1
}

# Get the latest version
LATEST_GO_VERSION=$(get_latest_go_version)

if [ -z "$LATEST_GO_VERSION" ] || [[ ! "$LATEST_GO_VERSION" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    print_error "Failed to fetch latest Go version from all sources."
    print_warning "Using fallback version go1.25.4"
    LATEST_GO_VERSION="go1.25.4"
else
    print_success "Successfully fetched latest Go version: $LATEST_GO_VERSION"
fi

# Check if Go is already installed
if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | awk '{print $3}')
    print_warning "Go is already installed: $CURRENT_VERSION"
    
    if [ "$CURRENT_VERSION" = "$LATEST_GO_VERSION" ]; then
        print_success "You already have the latest version of Go installed!"
        exit 0
    fi
    
    read -p "Do you want to upgrade from $CURRENT_VERSION to $LATEST_GO_VERSION? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    # Remove existing Go installation
    print_info "Removing existing Go installation..."
    $SUDO_CMD rm -rf /usr/local/go
fi

# Determine architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        GO_ARCH="amd64"
        ;;
    aarch64|arm64)
        GO_ARCH="arm64"
        ;;
    armv7l)
        GO_ARCH="armv6l"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

print_info "Detected architecture: $ARCH (Go arch: $GO_ARCH)"

# Download Go
GO_FILENAME="${LATEST_GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://golang.org/dl/${GO_FILENAME}"

print_info "Downloading Go from: $GO_URL"
cd /tmp
wget -O "$GO_FILENAME" "$GO_URL"

if [ ! -f "$GO_FILENAME" ]; then
    print_error "Failed to download Go archive"
    exit 1
fi

# Verify download (optional checksum verification)
print_info "Download completed. File size: $(du -h $GO_FILENAME | cut -f1)"

# Extract and install Go
print_info "Installing Go to /usr/local/go..."
$SUDO_CMD tar -C /usr/local -xzf "$GO_FILENAME"

# Clean up downloaded file
rm "$GO_FILENAME"

# Set up environment variables
print_info "Setting up environment variables..."

# Create Go workspace directories with proper ownership
if [[ $IS_ROOT == true ]]; then
    mkdir -p "$USER_HOME/go/"{bin,src,pkg}
    # Set proper ownership if running as root
    if [[ "$ACTUAL_USER" != "root" ]]; then
        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/go"
        print_info "Set ownership of Go workspace to $ACTUAL_USER"
    fi
else
    mkdir -p "$USER_HOME/go/"{bin,src,pkg}
fi

# Add Go to PATH and set GOPATH in .bashrc
if ! grep -q "# Go environment" "$USER_HOME/.bashrc"; then
    cat >> "$USER_HOME/.bashrc" << 'EOF'

# Go environment
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
EOF
    print_info "Added Go environment variables to ~/.bashrc"
    
    # Set proper ownership if running as root
    if [[ $IS_ROOT == true && "$ACTUAL_USER" != "root" ]]; then
        chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.bashrc"
    fi
fi

# Add Go to PATH and set GOPATH in .profile (for compatibility)
if ! grep -q "# Go environment" "$USER_HOME/.profile"; then
    cat >> "$USER_HOME/.profile" << 'EOF'

# Go environment
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
EOF
    print_info "Added Go environment variables to ~/.profile"
    
    # Set proper ownership if running as root
    if [[ $IS_ROOT == true && "$ACTUAL_USER" != "root" ]]; then
        chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.profile"
    fi
fi

# Source the environment for current session
export PATH=$PATH:/usr/local/go/bin:$USER_HOME/go/bin
export GOPATH=$USER_HOME/go
export GOROOT=/usr/local/go

# Verify installation
print_info "Verifying Go installation..."
if command -v go &> /dev/null; then
    GO_VERSION=$(go version)
    print_success "Go installation successful!"
    print_success "Version: $GO_VERSION"
    print_success "GOROOT: $(go env GOROOT)"
    print_success "GOPATH: $(go env GOPATH)"
else
    print_error "Go installation failed!"
    exit 1
fi

# Create a simple test program
print_info "Creating a test Go program..."
mkdir -p "$USER_HOME/go/src/hello"
cat > "$USER_HOME/go/src/hello/main.go" << 'EOF'
package main

import (
    "fmt"
    "runtime"
)

func main() {
    fmt.Println("Hello, Go! Installation successful!")
    fmt.Printf("Go version: %s\n", runtime.Version())
}
EOF

# Set proper ownership for test program
if [[ $IS_ROOT == true && "$ACTUAL_USER" != "root" ]]; then
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/go/src/hello"
fi

# Test the installation
print_info "Testing Go installation..."
cd "$USER_HOME/go/src/hello"
if [[ $IS_ROOT == true && "$ACTUAL_USER" != "root" ]]; then
    # Run test as the actual user
    if su - "$ACTUAL_USER" -c "cd $USER_HOME/go/src/hello && export PATH=/usr/local/go/bin:\$PATH && go run main.go"; then
        print_success "Go test program executed successfully!"
    else
        print_warning "Go test program failed, but Go is installed correctly."
    fi
else
    # Run test normally
    if go run main.go; then
        print_success "Go test program executed successfully!"
    else
        print_warning "Go test program failed, but Go is installed correctly."
    fi
fi

print_success "Go installation completed successfully!"
print_info "Please run 'source ~/.bashrc' or restart your terminal to use Go commands."
print_info "You can also run 'go version' to verify the installation."

# Display final information
echo
print_info "Installation Summary:"
echo "  - Go Version: $LATEST_GO_VERSION"
echo "  - Installation Path: /usr/local/go"
echo "  - GOPATH: $USER_HOME/go"
echo "  - Go workspace created at: $USER_HOME/go"
echo
print_info "Happy coding with Go! 🚀"