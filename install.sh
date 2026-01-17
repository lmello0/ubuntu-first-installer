#!/usr/bin/env bash
set -e

echo "=== Ubuntu First Installer ==="

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

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global core.editor "vim"

echo "Git configured:"
git config --global --list | grep user || true

################################
# Zsh + Oh My Zsh (non-interactive)
################################
echo "Installing Oh My Zsh..."
sudo chsh -s "$(which zsh)" "$USER" || echo "Warning: Could not change shell. Run 'chsh -s \$(which zsh)' manually."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

################################
# Zsh plugins
################################
echo "Installing Zsh plugins..."
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
  git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

################################
# .zshrc config
################################
ZSHRC="$HOME/.zshrc"

# Add plugins (idempotent)
if ! grep -q "zsh-syntax-highlighting" "$ZSHRC"; then
  sed -i 's/^plugins=(/plugins=(zsh-syntax-highlighting zsh-autosuggestions /' "$ZSHRC"
fi

# Add python alias
grep -q "alias python=python3" "$ZSHRC" || echo "alias python=python3" >> "$ZSHRC"

################################
# Go (latest)
################################
echo "Installing Go (latest)..."

OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

LATEST_GO=$(curl -s https://go.dev/VERSION?m=text)
GO_FILE="${LATEST_GO}.${OS}-${ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_FILE}"

curl -LO "$GO_URL"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "$GO_FILE"
rm -f "$GO_FILE"

grep -q "/usr/local/go/bin" "$ZSHRC" || echo 'export PATH=$PATH:/usr/local/go/bin' >> "$ZSHRC"

################################
# Rust + Cargo
################################
echo "Installing Rust..."
if ! command -v rustup >/dev/null 2>&1; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

source "$HOME/.cargo/env"

rustup self update
rustup update stable
rustup default stable

# Add Rust to .zshrc
if ! grep -q ".cargo/env" "$ZSHRC"; then
  echo 'source "$HOME/.cargo/env"' >> "$ZSHRC"
fi

################################
# bat via cargo
################################
echo "Installing bat..."
if ! command -v bat >/dev/null 2>&1; then
  cargo install bat
fi

# Add bat alias (now that bat is installed)
if command -v bat >/dev/null 2>&1; then
  grep -q "alias cat=bat" "$ZSHRC" || echo "alias cat=bat" >> "$ZSHRC"
fi

################################
# Python (latest) via pyenv
################################
echo "Installing Python via pyenv..."
if [ ! -d "$HOME/.pyenv" ]; then
  curl https://pyenv.run | bash
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Add pyenv to .zshrc
if ! grep -q "pyenv init" "$ZSHRC"; then
  cat >> "$ZSHRC" << 'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
fi

LATEST_PYTHON=$(pyenv install --list | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+$" | tail -1 | tr -d ' ')
echo "Installing Python $LATEST_PYTHON..."
pyenv install -s "$LATEST_PYTHON"
pyenv global "$LATEST_PYTHON"

################################
# pipenv
################################
echo "Installing pipenv..."
python -m pip install --upgrade pip setuptools wheel
python -m pip install --user pipenv

################################
# SSH key generation
################################
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
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

gh auth login

echo ""
echo "Uploading SSH key to GitHub..."
gh ssh-key add "$SSH_KEY.pub" --title "$(hostname)-$(date +%Y%m%d)" || echo "Warning: Could not upload SSH key. You may need to add it manually."

################################
# Done
################################
echo ""
echo "=================================="
echo "Installation complete!"
echo "=================================="
echo "Shell changed to Zsh. Please log out and log back in,"
echo "or run: exec zsh"
echo "=================================="
