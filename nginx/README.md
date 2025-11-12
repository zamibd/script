# Nginx Management Scripts

This repository contains scripts to manage Nginx installation, uninstallation, and SSL configuration.

## 1. Nginx Installation
To install Nginx, run the following one-liner command:

```bash
curl -s https://raw.githubusercontent.com/zamibd/script/main/nginx/install.sh | bash
```

## 2. Nginx Uninstallation
To uninstall Nginx, run the following one-liner command:

```bash
curl -s https://raw.githubusercontent.com/zamibd/script/main/nginx/uninstall.sh | bash
```

## 3. Nginx with SSL
To configure Nginx with SSL, run the following script:

```bash
curl -o ssl.sh https://raw.githubusercontent.com/zamibd/script/main/nginx/ssl.sh
chmod +x ssl.sh
./ssl.sh
 | bash
```

## Tested Operating Systems
- Ubuntu 24.04
