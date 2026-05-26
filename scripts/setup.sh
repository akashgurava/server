#!/bin/bash

# Set Git username and email
git config --global user.name "Akash Gurava"
git config --global user.email "akashgurava@outlook.com"

echo "1. Acquiring SUDO."
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
echo "1. Acquiring SUDO. Complete."

echo "2. Install Xcode CLI tools."
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode CLI tools..."
    xcode-select --install
    # Wait for the installation to complete
    until xcode-select -p &> /dev/null; do
        sleep 5
    done
fi
echo "2. Install Xcode CLI tools. Comeplete."

echo "3. Install brew."
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "3. Install brew. Complete."

echo "4. Install packages from Brewfile."
if [ -f "Brewfile" ]; then
    echo "Installing packages from Brewfile..."
    brew bundle --file="$Brewfile"
fi
echo "4. Install packages from Brewfile. Complete."

echo "5. Install Oh My Zsh."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended
else
    echo "Oh My Zsh already installed."
fi
# Ensure desired Oh My Zsh plugins are installed (idempotent)
ZSH_CUSTOM_DIR=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
    echo "Installing plugin: zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing plugin: zsh-syntax-highlighting"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
fi
echo "5. Install Oh My Zsh. Complete."

echo "6. Ensure Docker Compose v2 is discoverable by Docker CLI."
# Create per-user CLI plugins directory and symlink docker-compose (idempotent)
mkdir -p "$HOME/.docker/cli-plugins"
if command -v docker-compose >/dev/null 2>&1; then
    ln -sfn "$(which docker-compose)" "$HOME/.docker/cli-plugins/docker-compose"
fi

# If Docker config doesn't exist, create it with cliPluginsExtraDirs pointing to Homebrew's plugin dir
HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
mkdir -p "$HOME/.docker"
CONFIG_JSON="$HOME/.docker/config.json"
if [ ! -f "$CONFIG_JSON" ]; then
  cat > "$CONFIG_JSON" <<EOF
{
  "cliPluginsExtraDirs": [
    "${HOMEBREW_PREFIX}/lib/docker/cli-plugins"
  ]
}
EOF
fi
echo "6. Docker Compose v2 discovery configured."

brew services start colima