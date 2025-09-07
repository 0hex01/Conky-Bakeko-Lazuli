#!/bin/bash

# Exit on error
set -e

# Function to display usage information
show_usage() {
    echo "Usage: $0 [backup_file] [username]"
    echo "If no arguments are provided, the script will search for backup files and prompt for username."
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Default values
BACKUP_FILE=""
USERNAME=""

# Process command line arguments
if [ $# -eq 2 ]; then
    BACKUP_FILE="$1"
    USERNAME="$2"
elif [ $# -eq 1 ]; then
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
    else
        BACKUP_FILE="$1"
    fi
fi

# Find backup file if not provided
if [ -z "$BACKUP_FILE" ]; then
    echo "Searching for conky backup files..."
    BACKUP_FILES=($(find / -name "*conky*.tar.gz" -o -name "*conky*.zip" 2>/dev/null | grep -v "Permission denied" || true))
    
    if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
        echo "No conky backup files found. Please specify the backup file path manually."
        exit 1
    fi
    
    echo "Found the following backup files:"
    for i in "${!BACKUP_FILES[@]}"; do
        echo "$((i+1)). ${BACKUP_FILES[$i]}"
    done
    
    read -p "Enter the number of the backup file to use (or 0 to exit): " SELECTION
    
    if [ "$SELECTION" -eq 0 ] 2>/dev/null; then
        echo "Installation cancelled."
        exit 0
    elif [ "$SELECTION" -gt 0 ] && [ "$SELECTION" -le "${#BACKUP_FILES[@]}" ] 2>/dev/null; then
        BACKUP_FILE="${BACKUP_FILES[$((SELECTION-1))]}"
    else
        echo "Invalid selection. Exiting."
        exit 1
    fi
fi

# Get username if not provided
if [ -z "$USERNAME" ]; then
    echo "Available users on the system:"
    echo "----------------------------"
    getent passwd | grep -E '/home|/root' | cut -d: -f1 | sort | nl -w2 -s'. '
    echo "----------------------------"
    
    while true; do
        read -p "Enter the username to install conky for (or 'q' to quit): " USERNAME
        
        if [ "$USERNAME" = "q" ]; then
            echo "Installation cancelled."
            exit 0
        fi
        
        if id "$USERNAME" &>/dev/null; then
            break
        else
            echo "User '$USERNAME' does not exist. Please try again or enter 'q' to quit."
        fi
    done
fi

# Set user's home directory
USER_HOME="/home/$USERNAME"
if [ "$USERNAME" = "root" ]; then
    USER_HOME="/root"
fi

# Set target directories
CONKY_DIR="$USER_HOME/CascadeProjects/conky_theme"
AUTOSTART_DIR="$USER_HOME/.config/autostart"

# Create necessary directories
echo "Creating directories..."
mkdir -p "$CONKY_DIR"
mkdir -p "$AUTOSTART_DIR"

# Extract backup file
echo "Extracting backup file: $BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.tar.gz ]]; then
    tar -xzf "$BACKUP_FILE" -C "$CONKY_DIR" --strip-components=1
elif [[ "$BACKUP_FILE" == *.zip ]]; then
    unzip -q "$BACKUP_FILE" -d "$CONKY_DIR"
    # Move files from potential subdirectory to CONKY_DIR
    if [ "$(ls -1 "$CONKY_DIR" | wc -l)" -eq 1 ]; then
        SUBDIR="$(ls -1 "$CONKY_DIR" | head -1)"
        if [ -d "$CONKY_DIR/$SUBDIR" ]; then
            mv "$CONKY_DIR/$SUBDIR"/* "$CONKY_DIR/"
            rmdir "$CONKY_DIR/$SUBDIR"
        fi
    fi
else
    echo "Unsupported backup file format. Please use .tar.gz or .zip files."
    exit 1
fi

# Find conky config file
CONFIG_FILE=$(find "$CONKY_DIR" -name "*.conf" | head -1)
if [ -z "$CONFIG_FILE" ]; then
    echo "No conky configuration file found in the backup."
    exit 1
fi

# Create autostart entry
echo "Creating autostart entry..."
cat > "$AUTOSTART_DIR/start-conky.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=conky -c $CONFIG_FILE
Icon=conky
X-GNOME-Autostart-enabled=true
X-MATE-Autostart-enabled=true
NoDisplay=false
Hidden=false
Name=Conky
Comment=Start Conky on login
X-GNOME-Autostart-Delay=0
EOL

# Set permissions
echo "Setting permissions..."
chown -R "$USERNAME:$USERNAME" "$CONKY_DIR"
chown "$USERNAME:$USERNAME" "$AUTOSTART_DIR/start-conky.desktop"
chmod +x "$AUTOSTART_DIR/start-conky.desktop"

# Install conky if not installed
if ! command -v conky &> /dev/null; then
    echo "Conky not found. Installing conky..."
    apt-get update
    apt-get install -y conky-all
fi

echo "Installation complete!"
echo "Conky theme has been installed to: $CONKY_DIR"
echo "Autostart entry created at: $AUTOSTART_DIR/start-conky.desktop"
echo "Conky will start automatically when $USERNAME logs in."

# Ask if user wants to start conky now
read -p "Would you like to start conky now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo -u "$USERNAME" conky -c "$CONFIG_FILE" &
    echo "Conky started!"
fi
