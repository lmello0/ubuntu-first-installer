#!/usr/bin/env bash
# ==============================================================================
# Ubuntu Global Installer
# Run with: curl -fsSL <url> | sudo bash
# ==============================================================================
set -euo pipefail

echo "=== Ubuntu Global Installer ==="

# ------------------------------------------------------------------------------
# Guard: must run as root via sudo (not directly as root)
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "This script needs to be run with sudo."
  echo "Please run: sudo $0"
  exit 1
fi

if [ -z "${SUDO_USER:-}" ]; then
  echo "Error: SUDO_USER is not set. Please run this script with 'sudo bash' rather than as root directly."
  exit 1
fi

ACTUAL_USER="$SUDO_USER"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
ZSHRC="$ACTUAL_HOME/.zshrc"

################################
# Base packages
################################
echo "Installing base packages..."
apt update
apt install -y \
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
while [[ -z "${GIT_NAME:-}" ]]; do
  read -rp "Enter your Git name: " GIT_NAME
done

while [[ -z "${GIT_EMAIL:-}" ]]; do
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
chsh -s "$(which zsh)" "$ACTUAL_USER" || echo "Warning: Could not change shell. Run 'chsh -s \$(which zsh)' manually."

if [ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  sudo -u "$ACTUAL_USER" sh -c "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
fi

# Ensure .zshrc exists
touch "$ZSHRC"
chown "$ACTUAL_USER:$ACTUAL_USER" "$ZSHRC"

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

# Add plugins (idempotent)
if ! grep -q "zsh-syntax-highlighting" "$ZSHRC"; then
  sed -i 's/^plugins=(/plugins=(zsh-syntax-highlighting zsh-autosuggestions /' "$ZSHRC"
fi

# Add python alias
grep -q "alias python=python3" "$ZSHRC" || echo "alias python=python3" >> "$ZSHRC"

################################
# System-wide environment via profile.d
# (replaces fragile sed edits on /etc/environment and /etc/profile)
################################
echo "Configuring system-wide environment via /etc/profile.d/dev-tools.sh..."
cat > /etc/profile.d/dev-tools.sh << 'EOF'
# Dev tools – managed by ubuntu-first-installer
export PYENV_ROOT="/opt/pyenv"
export RUSTUP_HOME="/opt/rust/rustup"
export CARGO_HOME="/opt/rust/cargo"
export PATH="/opt/pyenv/bin:/opt/pyenv/shims:/opt/rust/cargo/bin:/usr/local/go/bin:$PATH"

# pyenv shell integration (completions, rehash hooks)
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
EOF
chmod +x /etc/profile.d/dev-tools.sh

################################
# Go (latest) - GLOBAL INSTALL
################################
echo "Installing Go globally (latest)..."

OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64)   ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv6l|armv7l) ARCH="armv6l" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
GO_FILE="${LATEST_GO}.${OS}-${ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_FILE}"

curl -LO "$GO_URL"
rm -rf /usr/local/go
tar -C /usr/local -xzf "$GO_FILE"
rm -f "$GO_FILE"

# Symlinks for sudo access
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

################################
# Rust + Cargo - GLOBAL INSTALL
################################
echo "Installing Rust globally..."

mkdir -p /opt/rust/rustup /opt/rust/cargo

export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo

if [ ! -f "/opt/rust/cargo/bin/rustup" ]; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path \
    --default-toolchain stable \
    --profile default
fi

/opt/rust/cargo/bin/rustup self update
/opt/rust/cargo/bin/rustup update stable
/opt/rust/cargo/bin/rustup default stable

# Symlinks for sudo access
ln -sf /opt/rust/cargo/bin/cargo   /usr/local/bin/cargo
ln -sf /opt/rust/cargo/bin/rustc   /usr/local/bin/rustc
ln -sf /opt/rust/cargo/bin/rustup  /usr/local/bin/rustup

export PATH=$PATH:/opt/rust/cargo/bin

################################
# bat via cargo - GLOBAL
################################
echo "Installing bat globally..."
if [ ! -f "/opt/rust/cargo/bin/bat" ]; then
  /opt/rust/cargo/bin/cargo install bat
fi

ln -sf /opt/rust/cargo/bin/bat /usr/local/bin/bat
grep -q "alias cat=bat" "$ZSHRC" || echo "alias cat=bat" >> "$ZSHRC"

################################
# eza via cargo - GLOBAL
################################
echo "Installing eza globally..."
if [ ! -f "/opt/rust/cargo/bin/eza" ]; then
  /opt/rust/cargo/bin/cargo install eza
fi

ln -sf /opt/rust/cargo/bin/eza /usr/local/bin/eza
grep -q "alias ls=eza" "$ZSHRC" || echo "alias ls=eza" >> "$ZSHRC"

################################
# Python (latest) - GLOBAL INSTALL via pyenv
################################
echo "Installing Python globally via pyenv..."

export PYENV_ROOT="/opt/pyenv"

if [ ! -d "$PYENV_ROOT" ]; then
  git clone https://github.com/pyenv/pyenv.git /opt/pyenv
fi

export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# -- FIX: shared group so $ACTUAL_USER can write shims without sudo --
groupadd -f pyenv-users
usermod -aG pyenv-users "$ACTUAL_USER"

chown -R root:pyenv-users /opt/pyenv
chmod -R g+rwx /opt/pyenv
# setgid on all dirs: new files (shims) inherit pyenv-users group automatically
find /opt/pyenv -type d -exec chmod g+s {} \;

LATEST_PYTHON=$(pyenv install --list | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+$" | tail -1 | tr -d ' ')
echo "Installing Python $LATEST_PYTHON globally..."
pyenv install -s "$LATEST_PYTHON"
pyenv global "$LATEST_PYTHON"

# Re-apply permissions after pyenv creates new shim files during install
chown -R root:pyenv-users /opt/pyenv/shims
chmod -R g+rwx /opt/pyenv/shims

PYTHON_VERSION=$(pyenv global)

# Symlinks for sudo access
ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/python3" /usr/local/bin/python
ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/python3" /usr/local/bin/python3
ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/pip3"    /usr/local/bin/pip
ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/pip3"    /usr/local/bin/pip3

################################
# sudoers: preserve dev-tool env vars + correct secure_path
################################
cat > /etc/sudoers.d/dev-tools << 'EOF'
Defaults env_keep += "PYENV_ROOT RUSTUP_HOME CARGO_HOME"
Defaults secure_path="/opt/pyenv/shims:/opt/pyenv/bin:/opt/rust/cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 0440 /etc/sudoers.d/dev-tools

################################
# pipenv - GLOBAL INSTALL
################################
echo "Installing pipenv globally..."
python -m pip install --upgrade pip setuptools wheel
python -m pip install pipenv

ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/pipenv" /usr/local/bin/pipenv

################################
# ipython - GLOBAL INSTALL
# FIX: was incorrectly symlinking to /usr/local/bin/pipenv
################################
echo "Installing ipython globally..."
python -m pip install ipython

ln -sf "/opt/pyenv/versions/$PYTHON_VERSION/bin/ipython" /usr/local/bin/ipython

################################
# .zshrc: minimal pyenv shell integration
# PATH and exports are already handled by /etc/profile.d/dev-tools.sh
# Only add the shell-init hook here (completions, cd rehash, etc.)
################################
if ! grep -q "pyenv init" "$ZSHRC"; then
  cat >> "$ZSHRC" << 'EOF'

# pyenv shell integration (completions + rehash on cd)
# PATH is set system-wide via /etc/profile.d/dev-tools.sh
eval "$(pyenv init -)"
EOF
fi

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
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  apt update
  apt install -y gh
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
sudo -u "$ACTUAL_USER" gh ssh-key add "$SSH_KEY.pub" \
  --title "$(hostname)-$(date +%Y%m%d)" \
  || echo "Warning: Could not upload SSH key. You may need to add it manually."

################################
# Done
################################
echo ""
echo "=================================="
echo "Installation complete!"
echo "=================================="
echo "All tools installed globally:"
echo "  - Go:             /usr/local/go"
echo "  - Rust:           /opt/rust"
echo "  - Python (pyenv): /opt/pyenv"
echo ""
echo "Symlinks in /usr/local/bin:"
echo "  python, python3, pip, pip3"
echo "  go, gofmt"
echo "  cargo, rustc, rustup"
echo "  pipenv, ipython, bat, eza"
echo ""
echo "System-wide env configured in: /etc/profile.d/dev-tools.sh"
echo ""
echo "⚠️  WSL users: run 'wsl --shutdown' from PowerShell then reopen"
echo "   your terminal to pick up group membership (pyenv-users) and"
echo "   the new PATH. A simple logout is not always enough in WSL."
echo ""
echo "To verify immediately in your current shell:"
echo "  source /etc/profile.d/dev-tools.sh"
echo "  exec zsh"
echo "=================================="