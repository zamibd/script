# Go Programming Language Management Scripts

This repository contains scripts to manage Go installation and uninstallation on Ubuntu servers.

## 1. Go Installation
To install the latest version of Go, run the following one-liner command:

```bash
curl -s https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/install.sh | bash
```

### Manual Installation
Alternatively, you can download and run the script manually:

```bash
wget https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/install.sh
chmod +x install.sh
./install.sh
```

## 2. Go Uninstallation
To uninstall Go completely (non-interactive), run the following one-liner command:

```bash
curl -s https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/uninstall.sh | bash
```

### Manual Uninstallation
```bash
wget https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/uninstall.sh
chmod +x uninstall.sh
./uninstall.sh
```

## Features

### Installation Script
- **Latest Version Detection**: Automatically fetches and installs the latest stable Go version (currently Go 1.25.4)
- **Multi-Method Fallback**: Uses 4 different methods to ensure reliable version detection
- **Architecture Support**: Supports amd64, arm64, and armv6l architectures
- **Root/User Context**: Works with both root and regular user execution
- **Environment Setup**: Configures GOPATH, GOROOT, and PATH variables
- **Workspace Creation**: Sets up proper Go workspace structure
- **Upgrade Detection**: Detects existing installations and offers upgrades (interactive prompt)
- **Verification**: Includes test program to verify installation

### Uninstallation Script
- **Complete Removal**: Removes Go installation, workspace, and all configurations
- **Non-Interactive**: Runs automatically without user prompts (perfect for automation)
- **Safe Cleanup**: Backs up configuration files before modification
- **Environment Cleanup**: Removes Go variables from .bashrc, .profile, .zshrc, .bash_profile
- **Cache Removal**: Cleans build cache and module cache (automatic)
- **Package Manager**: Removes Go packages installed via apt
- **Process Management**: Stops running Go processes before removal

## Installation Details

### What Gets Installed
- **Go Binary**: Latest stable version installed to `/usr/local/go`
- **Environment Variables**: GOPATH, GOROOT, and PATH configuration
- **Workspace**: Creates `$HOME/go/{bin,src,pkg}` directory structure
- **Dependencies**: curl, wget, tar, git, build-essential

### What Gets Removed (Uninstall)
- **Go Installation**: `/usr/local/go` directory
- **Go Workspace**: `$HOME/go` directory (includes all projects!)
- **Environment Variables**: From all shell configuration files
- **Build Cache**: `$HOME/.cache/go-build`
- **Module Cache**: `$HOME/go/pkg/mod`
- **System Binaries**: Go-related symlinks from `/usr/local/bin`
- **Package Manager**: Go packages installed via apt

## Tested Operating Systems
- Ubuntu 24.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 20.04 LTS
- Other Debian-based distributions

## Supported Architectures
- x86_64 (amd64)
- ARM64 (aarch64)
- ARMv7 (armv6l)

## Requirements
- **Operating System**: Ubuntu/Debian-based Linux distribution
- **Network**: Internet connection for downloading Go
- **Permissions**: sudo privileges (for system-wide installation)
- **Dependencies**: Basic system tools (automatically installed if missing)

## Usage Examples

### Basic Installation
```bash
# Install latest Go version
curl -s https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/install.sh | bash

# Verify installation
source ~/.bashrc
go version
```

### Complete Removal
```bash
# Remove everything (no prompts)
curl -s https://raw.githubusercontent.com/zamibd/script/main/pro-lang/Go/uninstall.sh | bash

# Restart terminal or source config
source ~/.bashrc
```

### Check Installation
After installation, verify Go is working:
```bash
go version
go env GOROOT
go env GOPATH
```

## Environment Variables Set
- `GOROOT`: `/usr/local/go` (Go installation directory)
- `GOPATH`: `$HOME/go` (Go workspace directory)
- `PATH`: Updated to include `$GOROOT/bin` and `$GOPATH/bin`

## Troubleshooting

### Installation Issues
1. **Permission Denied**: Run with sudo or as root user
2. **Network Issues**: Check internet connection and firewall settings
3. **Architecture Error**: Verify your system architecture is supported

### After Installation
1. **Go command not found**: Run `source ~/.bashrc` or restart terminal
2. **Version Mismatch**: Check if multiple Go installations exist
3. **Workspace Issues**: Verify `$GOPATH` is set correctly

### Uninstallation Issues
1. **Permission Denied**: Run with sudo privileges
2. **Files Remain**: Manually check `/usr/local/go` and `$HOME/go`
3. **Environment Variables**: Manually edit shell configuration files if needed

## Version Information
- **Script Version**: Latest (Auto-updating)
- **Go Version**: Automatically detects and installs latest stable release
- **Fallback Version**: Go 1.25.4 (if auto-detection fails)

## Security Notes
- Scripts can be run as root or regular user (with sudo)
- Configuration files are backed up before modification
- Proper file ownership is maintained when run as root
- No sensitive information is stored or transmitted

## Important Notes

### Installation Behavior
- **Interactive Upgrade**: If Go is already installed, the script will prompt for confirmation to upgrade
- **Automatic Dependencies**: Installs required system packages (curl, wget, tar, git, build-essential)
- **System Updates**: Performs `apt update && apt upgrade` during installation
- **Test Program**: Creates and runs a test Go program to verify installation success

### Uninstallation Behavior  
- **Fully Automated**: No user prompts - removes everything automatically
- **Backup Safety**: Creates timestamped backups in `~/.go_uninstall_backup_YYYYMMDD_HHMMSS/`
- **Process Cleanup**: Automatically stops any running Go processes before removal
- **Complete Cleanup**: Removes both manually installed Go and apt-installed Go packages

## Architecture Detection
The scripts automatically detect your system architecture:
```bash
# Supported mappings:
x86_64    -> amd64
aarch64   -> arm64  
arm64     -> arm64
armv7l    -> armv6l
```

## Version Detection Methods
The install script uses multiple fallback methods for reliability:
1. **Primary**: `https://go.dev/VERSION?m=text`
2. **Fallback 1**: `https://golang.org/VERSION?m=text`  
3. **Fallback 2**: GitHub releases API
4. **Fallback 3**: Parse from Go downloads page
5. **Final Fallback**: go1.25.4 (hardcoded)