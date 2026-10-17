#!/data/data/com.termux/files/usr/bin/bash
# TAD installer — clone (or update) the repository, then set up the toolchain.
set -euo pipefail

REPO="${TAD_REPO:-https://github.com/mhs003/TAD.git}"
DIR="${TAD_INSTALL_DIR:-$HOME/.local/share/TAD}"

command -v git >/dev/null 2>&1 || pkg install -y git

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only
else
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 "$REPO" "$DIR"
fi

exec "$DIR/bin/tad-setup" "$@"
