#!/usr/bin/env bash
set -e

echo "=== Ubuntu Global Installer ==="

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script needs to be run with sudo for global installations."
  echo "Please run: sudo $0"
  exit 1
fi

# Get the actual user (not root) who invoked sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

################################
# Base packages
################################
echo "Installing base packages..."
sudo apt update
sudo apt install -y \
  curl \
  git \
  zsh \
  build-essential \
  make \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  wget \
  llvm \
  libncursesw5-dev \
  xz-utils \
  tk-dev \
  libxml2-dev \
  libxmlsec1-dev \
  libffi-dev \
  liblzma-dev \
  gnupg \
  ca-certificates

################################
# Git config (prompted)
################################
echo "Configuring Git..."
while [[ -z "$GIT_NAME" ]]; do
  read -rp "Enter your Git name: " GIT_NAME
done

while [[ -z "$GIT_EMAIL" ]]; do
  read -rp "Enter your Git email: " GIT_EMAIL
done

sudo -u "$ACTUAL_USER" git config --global user.name "$GIT_NAME"
sudo -u "$ACTUAL_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$ACTUAL_USER" git config --global init.defaultBranch main
sudo -u "$ACTUAL_USER" git config --global pull.rebase false
sudo -u "$ACTUAL_USER" git config --global push.autoSetupRemote true
sudo -u "$ACTUAL_USER" git config --global core.editor "vim"

echo "Git configured:"
sudo -u "$ACTUAL_USER" git config --global --list | grep user || true

################################
# Zsh + Oh My Zsh (non-interactive)
################################
echo "Installing Oh My Zsh..."
sudo chsh -s "$(which zsh)" "$ACTUAL_USER" || echo "Warning: Could not change shell. Run 'chsh -s \$(which zsh)' manually."

if [ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  sudo -u "$ACTUAL_USER" sh -c "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
fi

################################
# Zsh plugins
################################
echo "Installing Zsh plugins..."
ZSH_CUSTOM="$ACTUAL_HOME/.oh-my-zsh/custom"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
  sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
  sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

################################
# .zshrc config
################################
ZSHRC="$ACTUAL_HOME/.zshrc"

# Add plugins (idempotent)
if ! grep -q "zsh-syntax-highlighting" "$ZSHRC"; then
  sed -i 's/^plugins=(/plugins=(zsh-syntax-highlighting zsh-autosuggestions /' "$ZSHRC"
fi

# Add python alias
grep -q "alias python=python3" "$ZSHRC" || echo "alias python=python3" >> "$ZSHRC"

################################
# Go (latest) - GLOBAL INSTALL
################################
echo "Installing Go globally (latest)..."

OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    ;;
  armv6l|armv7l)
    ARCH="armv6l"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
GO_FILE="${LATEST_GO}.${OS}-${ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_FILE}"

curl -LO "$GO_URL"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "$GO_FILE"
rm -f "$GO_FILE"

# Add Go to system-wide PATH
if ! grep -q "/usr/local/go/bin" /etc/environment; then
  echo 'PATH="/usr/local/go/bin:$PATH"' >> /etc/environment
fi

if ! grep -q "/usr/local/go/bin" /etc/profile; then
  echo 'export PATH=$PATH:/usr/local/go/bin' | tee -a /etc/profile
fi

# Create symlink for easy sudo access
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Also add to current user's .zshrc
grep -q "/usr/local/go/bin" "$ZSHRC" || echo 'export PATH=$PATH:/usr/local/go/bin' >> "$ZSHRC"

################################
# Rust + Cargo - GLOBAL INSTALL
################################
echo "Installing Rust globally..."

# Create directories first
mkdir -p /opt/rust/rustup /opt/rust/cargo
chown -R root:root /opt/rust

# Set environment for installation
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo

if [ ! -f "/opt/rust/cargo/bin/rustup" ]; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path \
    --default-toolchain stable \
    --profile default
fi

# Update and set default
/opt/rust/cargo/bin/rustup self update
/opt/rust/cargo/bin/rustup update stable
/opt/rust/cargo/bin/rustup default stable

# Add Rust to system-wide PATH
if ! grep -q "/opt/rust/cargo/bin" /etc/environment; then
  sed -i 's|PATH="\(.*\)"|PATH="/opt/rust/cargo/bin:\1"|' /etc/environment 2>/dev/null || \
  echo 'PATH="/opt/rust/cargo/bin:$PATH"' >> /etc/environment
fi

if ! grep -q "/opt/rust/cargo/bin" /etc/profile; then
  cat << 'EOF' | tee -a /etc/profile
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export PATH=$PATH:/opt/rust/cargo/bin
EOF
fi

# Create symlinks for easy sudo access
ln -sf /opt/rust/cargo/bin/cargo /usr/local/bin/cargo
ln -sf /opt/rust/cargo/bin/rustc /usr/local/bin/rustc
ln -sf /opt/rust/cargo/bin/rustup /usr/local/bin/rustup

# Also add to current user's .zshrc
if ! grep -q "/opt/rust/cargo/bin" "$ZSHRC"; then
  cat >> "$ZSHRC" << 'EOF'
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export PATH=$PATH:/opt/rust/cargo/bin
EOF
fi

# Source for current session
export PATH=$PATH:/opt/rust/cargo/bin

################################
# bat via cargo - GLOBAL
################################
echo "Installing bat globally..."
if ! command -v bat >/dev/null 2>&1; then
  /opt/rust/cargo/bin/cargo install bat
fi

# Create symlink
ln -sf /opt/rust/cargo/bin/bat /usr/local/bin/bat

# Add bat alias
if command -v bat >/dev/null 2>&1 || [ -f "/opt/rust/cargo/bin/bat" ]; then
  grep -q "alias cat=bat" "$ZSHRC" || echo "alias cat=bat" >> "$ZSHRC"
fi

################################
# eza via cargo - GLOBAL
################################
echo "Installing eza globally..."
if ! command -v eza >/dev/null 2>&1; then
  /opt/rust/cargo/bin/cargo install eza
fi

# Create symlink
ln -sf /opt/rust/cargo/bin/eza /usr/local/bin/eza

# Add eza alias
if command -v eza >/dev/null 2>&1 || [ -f "/opt/rust/cargo/bin/eza" ]; then
  grep -q "alias ls=eza" "$ZSHRC" || echo "alias ls=eza" >> "$ZSHRC"
fi

################################
# Python (latest) - GLOBAL INSTALL
################################
echo "Installing Python globally via pyenv..."

# Install pyenv globally to /opt/pyenv
export PYENV_ROOT="/opt/pyenv"

if [ ! -d "$PYENV_ROOT" ]; then
  mkdir -p /opt/pyenv
  git clone https://github.com/pyenv/pyenv.git /opt/pyenv
  chown -R root:root /opt/pyenv
fi

export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Add pyenv to system-wide PATH
if ! grep -q "PYENV_ROOT" /etc/environment; then
  sed -i 's|PATH="\(.*\)"|PATH="/opt/pyenv/bin:\1"|' /etc/environment 2>/dev/null || \
  echo 'PATH="/opt/pyenv/bin:$PATH"' >> /etc/environment
fi

if ! grep -q "PYENV_ROOT" /etc/profile; then
  cat << 'EOF' | tee -a /etc/profile
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
fi

# Create sudoers file to preserve PYENV environment
cat << 'EOF' > /etc/sudoers.d/pyenv
Defaults env_keep += "PYENV_ROOT"
Defaults secure_path="/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 0440 /etc/sudoers.d/pyenv

# Also add to current user's .zshrc
if ! grep -q "PYENV_ROOT" "$ZSHRC"; then
  cat >> "$ZSHRC" << 'EOF'

# pyenv
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
fi

LATEST_PYTHON=$(pyenv install --list | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+$" | tail -1 | tr -d ' ')
echo "Installing Python $LATEST_PYTHON globally..."
pyenv install -s "$LATEST_PYTHON"
pyenv global "$LATEST_PYTHON"

# Create symlinks for easy sudo access
PYTHON_VERSION=$(pyenv global)
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/python3 /usr/local/bin/python
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/python3 /usr/local/bin/python3
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/pip3 /usr/local/bin/pip
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/pip3 /usr/local/bin/pip3

################################
# pipenv - GLOBAL INSTALL
################################
echo "Installing pipenv globally..."
python -m pip install --upgrade pip setuptools wheel
python -m pip install pipenv

# Create symlink for pipenv
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/pipenv /usr/local/bin/pipenv

################################
# ipython - GLOBAL INSTALL
################################
echo "Installing ipython globally..."
python -m pip install ipython

# Create symlink for ipython
ln -sf /opt/pyenv/versions/$PYTHON_VERSION/bin/ipython /usr/local/bin/pipenv

################################
# SSH key generation
################################
SSH_KEY="$ACTUAL_HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
  echo "Generating SSH key..."
  sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_HOME/.ssh"
  sudo -u "$ACTUAL_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
fi

################################
# GitHub CLI + upload key
################################
if ! command -v gh >/dev/null 2>&1; then
  echo "Installing GitHub CLI..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  sudo apt update
  sudo apt install -y gh
fi

echo ""
echo "=================================="
echo "GitHub Authentication Required"
echo "=================================="
echo "The script will now open GitHub CLI authentication."
echo "Please follow the prompts to authenticate."
echo ""
read -rp "Press Enter to continue..."

sudo -u "$ACTUAL_USER" gh auth login

echo ""
echo "Uploading SSH key to GitHub..."
sudo -u "$ACTUAL_USER" gh ssh-key add "$SSH_KEY.pub" --title "$(hostname)-$(date +%Y%m%d)" || echo "Warning: Could not upload SSH key. You may need to add it manually."

################################
# Done
################################
echo ""
echo "=================================="
echo "Installation complete!"
echo "=================================="
echo "All tools installed globally:"
echo "  - Go: /usr/local/go"
echo "  - Rust: /opt/rust"
echo "  - Python (pyenv): /opt/pyenv"
echo ""
echo "Symlinks created in /usr/local/bin for sudo access:"
echo "  - python, python3, pip, pip3"
echo "  - go, cargo, rustc, rustup"
echo "  - pipenv, bat, eza"
echo ""
echo "You can now use these commands with sudo:"
echo "  sudo python --version"
echo "  sudo go version"
echo "  sudo cargo --version"
echo "  sudo pipenv --version"
echo ""
echo "To use immediately in your shell, run:"
echo "  source /etc/profile"
echo "  exec zsh"
echo ""
echo "Or simply log out and log back in."
echo "=================================="
