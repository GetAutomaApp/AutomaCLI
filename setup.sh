#!/bin/bash

# Define variables
CONFIG_DIR="$HOME/.config/automacli"
CONFIG_FILE="$CONFIG_DIR/config.json"
REPO_URL="https://github.com/GetAutomaApp/AutomaCLI.git"
REPO_DIR="$HOME/.automacli_repo" # Default clone location

# Check if config file exists and warn
if [ -f "$CONFIG_FILE" ]; then
    echo "Warning: Existing configuration file at $CONFIG_FILE will be overwritten."
    if [ "$AUTOMA_FORCE_OVERWRITE" != "true" ]; then
        echo "Error: Configuration file already exists at $CONFIG_FILE. To overwrite, set AUTOMA_FORCE_OVERWRITE=true."
        echo "Example: AUTOMA_FORCE_OVERWRITE=true curl -sSL https://raw.githubusercontent.com/GetAutomaApp/AutomaCLI/main/setup.sh | bash"
        exit 1
    fi
fi

# Clone the repository
echo "Cloning AutomaCLI repository into $REPO_DIR..."
if [ -d "$REPO_DIR" ]; then
    echo "Repository directory $REPO_DIR already exists. Pulling latest changes..."
    (cd "$REPO_DIR" && git pull) || { echo "Failed to pull latest changes."; exit 1; }
else
    git clone "$REPO_URL" "$REPO_DIR" || { echo "Failed to clone repository."; exit 1; }
fi

# Build the project
echo "Building AutomaCLI..."
(cd "$REPO_DIR" && swift build -c release) || { echo "Failed to build AutomaCLI."; exit 1; }

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR" || { echo "Failed to create config directory."; exit 1; }

# Create config file
echo "Creating configuration file at $CONFIG_FILE..."
cat << EOF > "$CONFIG_FILE"
{
  "repoPath": "$REPO_DIR"
}
EOF

echo "Setup complete. AutomaCLI built from source in $REPO_DIR and config saved to $CONFIG_FILE."

# Create a symbolic link to the binary
BIN_PATH="$REPO_DIR/.build/release/automa"
LINK_PATH="/usr/local/bin/automa"

echo "Creating symbolic link for AutomaCLI..."
if [ -f "$LINK_PATH" ]; then
    echo "Removing existing symbolic link at $LINK_PATH"
    sudo rm "$LINK_PATH"
fi
sudo ln -s "$BIN_PATH" "$LINK_PATH" || echo "Warning: Failed to create symbolic link. You may need to add /usr/local/bin to your PATH or run the script with appropriate permissions."

echo "You can now run AutomaCLI using the 'automa' command."

