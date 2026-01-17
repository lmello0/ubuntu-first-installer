#!/usr/bin/env bash
set -e

echo "=== Ubuntu First Installer ==="

################################
# Base packages
################################
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
read -rp "Enter your Git name: " GIT_NAME
read -rp "Enter your Git email: " GIT_EMAIL

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global core.editor "vim"

echo "Git configured:"
git config --global --list | grep user

################################
# Zsh + Oh My Zsh (non-interactive)
################################
echo "Installing Oh My Zsh..."
chsh -s "$(which zsh)"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

################################
# Zsh plugins
################################
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

sed -i 's/plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting zsh-autosuggestions)/' "$ZSHRC" || true

grep -q "alias python=python3" "$ZSHRC" || echo "alias python=python3" >> "$ZSHRC"
grep -q "alias cat=bat" "$ZSHRC" || echo "alias cat=bat" >> "$ZSHRC"

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

grep -q "/usr/local/go/bin" "$ZSHRC" || echo 'export PATH=$PATH:/usr/local/go/bin' >> "$ZSHRC"

################################
# Rust + Cargo
################################
if ! command -v rustup >/dev/null 2>&1; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

source "$HOME/.cargo/env"

rustup self update
rustup update stable
rustup default stable

################################
# bat via cargo
################################
if ! command -v bat >/dev/null 2>&1; then
  cargo install bat
fi

################################
# Python (latest) via pyenv
################################
if [ ! -d "$HOME/.pyenv" ]; then
  curl https://pyenv.run | bash
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

LATEST_PYTHON=$(pyenv install --list | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+$" | tail -1 | tr -d ' ')
pyenv install -s "$LATEST_PYTHON"
pyenv global "$LATEST_PYTHON"

################################
# pipenv
################################
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

eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY"

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

echo "Authenticating with GitHub..."
gh auth login

echo "Uploading SSH key to GitHub..."
gh ssh-key add "$SSH_KEY.pub" --title "$(hostname)-$(date +%Y%m%d)"

################################
# Done
################################
echo "=================================="
echo "Installation complete!"
echo "Restart your terminal or run: exec zsh"
echo "=================================="
