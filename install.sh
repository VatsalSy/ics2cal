#!/usr/bin/env bash
set -euo pipefail

# install.sh — build and install the ics2cal CLI on macOS
# Usage:
#   ./install.sh                         # build release, install to /usr/local/bin
#   ./install.sh --prefix /opt/homebrew  # custom prefix (installs to <prefix>/bin)
#   ./install.sh --prefix=/opt/homebrew  # same as above (= syntax supported)
#   ./install.sh --user                  # install to $HOME/bin

prefix="/usr/local"; user_install=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix=*)
      value="${1#*=}"
      if [[ -z "$value" || "${value:0:1}" == "-" ]]; then
        echo "Error: --prefix requires a non-empty value" >&2
        exit 2
      fi
      prefix="$value"
      shift
      ;;
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "Error: --prefix requires a value" >&2
        exit 2
      fi
      value="$2"
      if [[ -z "$value" || "${value:0:1}" == "-" ]]; then
        echo "Error: --prefix requires a non-empty value" >&2
        exit 2
      fi
      prefix="$value"
      shift 2
      ;;
    --user)
      user_install=true
      shift
      ;;
    -h|--help)
      echo "See script header for usage"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: Swift toolchain not found. Please install Xcode or Swift." >&2
  exit 1
fi

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
err_file=$(mktemp)
if ! install -m 0755 "$src" "$dest" 2>"$err_file"; then
  if grep -qi "permission denied" "$err_file"; then
    echo "Elevated privileges required to write to $dest_dir"
    rm -f "$err_file"
    sudo install -m 0755 "$src" "$dest"
  else
    echo "Failed to install to $dest:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
else
  rm -f "$err_file"
fi

if ! printf '%s\n' ":${PATH:-}:" | grep -qF ":$dest_dir:"; then
  echo "ℹ️  Ensure $dest_dir is on your PATH. Example:"
  echo "    export PATH=\"$dest_dir:\$PATH\""
fi

installed_msg=$("$dest" help 2>/dev/null | sed -n '/./{p;q;}') || true
default_name="$(basename "$dest")"
echo "✅ Installed: ${installed_msg:-$default_name}"
