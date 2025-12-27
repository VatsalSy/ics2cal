#!/usr/bin/env bash
set -euo pipefail

# install.sh — build and install the ics2cal CLI on macOS
# Usage:
#   ./install.sh                      # build release, install to /usr/local/bin
#   ./install.sh --prefix /opt/homebrew  # custom prefix (installs to <prefix>/bin)
#   ./install.sh --user               # install to $HOME/bin

prefix="/usr/local"; user_install=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) prefix="${2:-/usr/local}"; shift 2 ;;
    --user) user_install=true; shift ;;
    -h|--help) echo "See script header for usage"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

echo "🔧 Building ics2cal (release)…"
swift build -c release

src=".build/release/ics2cal"
if [[ ! -x "$src" ]]; then
  echo "Build succeeded but binary not found at $src" >&2
  exit 1
fi

if $user_install; then
  dest_dir="$HOME/bin"
else
  dest_dir="$prefix/bin"
fi
mkdir -p "$dest_dir"
dest="$dest_dir/ics2cal"

echo "🚚 Installing to $dest"
if install -m 0755 "$src" "$dest" 2>/dev/null; then
  :
else
  echo "Elevated privileges required to write to $dest_dir"
  sudo install -m 0755 "$src" "$dest"
fi

if ! printf '%s\n' ":${PATH:-}:" | grep -qxF ":$dest_dir:"; then
  echo "ℹ️  Ensure $dest_dir is on your PATH. Example:"
  echo "    export PATH=\"$dest_dir:\$PATH\""
fi

echo "✅ Installed: $("$dest" help | head -n 1 || echo ics2cal)"
