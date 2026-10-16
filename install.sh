#!/bin/sh
set -e

die() { echo "fatal: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [TEAM_ID | --adhoc | --uninstall | --help]

Options:
  TEAM_ID       10-character Apple Developer Team ID (auto-detected if omitted)
  --adhoc       Use ad-hoc signing (CODE_SIGN_IDENTITY = -) without a certificate
  --uninstall   Remove hooks and restore git tracking on patched files
  -h, --help    Show this help message
EOF
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
HOOKS_DIR=$(git rev-parse --git-path hooks)

# --- Uninstall ---
if [ "$1" = "--uninstall" ]; then
  rm -f "$HOOKS_DIR/post-checkout" "$HOOKS_DIR/post-merge"
  find . -name "project.pbxproj" -not -path "*/Pods/*" -not -path "*/.build/*" -not -path "*/DerivedData/*" | while read -r file; do
    git update-index --no-assume-unchanged "$file" 2>/dev/null || true
  done
  find . -maxdepth 3 -name "*.xcconfig" -not -path "*/.git/*" -not -path "*/Pods/*" -not -path "*/build/*" -not -path "*/DerivedData/*" -not -path "*/.build/*" | while read -r file; do
    git update-index --no-assume-unchanged "$file" 2>/dev/null || true
  done
  echo "Done! xcode-team-patcher hooks removed."
  exit 0
fi

# --- Determine mode ---
MODE="team"
team=""

if [ "$1" = "--adhoc" ]; then
  MODE="adhoc"
elif [ -n "$1" ]; then
  case "$1" in
    -*) die "unknown option: $1 (run with --help for usage)" ;;
  esac
  team="$1"
else
  certs=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" || true)
  count=$(printf '%s\n' "$certs" | grep -c "Apple Development" 2>/dev/null || true)

  if [ "$count" -eq 0 ]; then
    echo "info: no Apple Development certificate found, using ad-hoc signing"
    MODE="adhoc"
  elif [ "$count" -eq 1 ]; then
    team=$(printf '%s\n' "$certs" | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')
  else
    echo "Multiple Apple Development certificates found:"
    printf '%s\n' "$certs" | cat -n
    printf "Select [1-%d] (default 1): " "$count"
    if [ -r /dev/tty ]; then
      read -r choice </dev/tty
    else
      choice=1
    fi
    choice=${choice:-1}
    team=$(printf '%s\n' "$certs" | sed -n "${choice}p" | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')
  fi

  [ "$MODE" = "team" ] && [ -z "$team" ] && die "failed to detect team id"
fi

if [ "$MODE" = "team" ]; then
  printf '%s\n' "$team" | grep -qE '^[A-Z0-9]{10}$' || die "invalid Team ID '$team' (expected 10 uppercase alphanumeric characters)"
fi

mkdir -p "$HOOKS_DIR"

# --- Generate hook ---
if [ "$MODE" = "adhoc" ]; then
  cat > "$HOOKS_DIR/post-checkout" << 'HOOK'
#!/bin/sh
# xcode-team-patcher: ad-hoc signing (no certificate needed)
find . -name "project.pbxproj" -not -path "*/Pods/*" -not -path "*/.build/*" -not -path "*/DerivedData/*" | while read -r proj; do
  sed -i '' -E 's/DEVELOPMENT_TEAM *= *[^;]*;/DEVELOPMENT_TEAM = "";/g' "$proj"
  sed -i '' -E 's/"DEVELOPMENT_TEAM\[sdk=macosx\*\]" *= *[^;]*;/"DEVELOPMENT_TEAM[sdk=macosx*]" = "";/g' "$proj"
  git update-index --assume-unchanged "$proj" 2>/dev/null || true
done
find . -maxdepth 3 -name "*.xcconfig" -not -path "*/.git/*" -not -path "*/Pods/*" -not -path "*/build/*" -not -path "*/DerivedData/*" -not -path "*/.build/*" | while read -r xcconfig; do
  sed -i '' -E "s/DEVELOPMENT_TEAM *= *.*/DEVELOPMENT_TEAM =/" "$xcconfig"
  sed -i '' -E "s/CODE_SIGN_IDENTITY *= *.*/CODE_SIGN_IDENTITY = -/" "$xcconfig"
  sed -i '' -E "s/CODE_SIGN_STYLE *= *.*/CODE_SIGN_STYLE = Manual/" "$xcconfig"
  git update-index --assume-unchanged "$xcconfig" 2>/dev/null || true
done
HOOK
else
  cat > "$HOOKS_DIR/post-checkout" << HOOK
#!/bin/sh
# xcode-team-patcher: team signing with ${team}
team="${team}"
find . -name "project.pbxproj" -not -path "*/Pods/*" -not -path "*/.build/*" -not -path "*/DerivedData/*" | while read -r proj; do
  sed -i '' -E "s/DEVELOPMENT_TEAM *= *[^;]*;/DEVELOPMENT_TEAM = \${team};/g" "\$proj"
  sed -i '' -E "s/\"DEVELOPMENT_TEAM\[sdk=macosx\*\]\" *= *[^;]*;/\"DEVELOPMENT_TEAM[sdk=macosx*]\" = \${team};/g" "\$proj"
  git update-index --assume-unchanged "\$proj" 2>/dev/null || true
done
find . -maxdepth 3 -name "*.xcconfig" -not -path "*/.git/*" -not -path "*/Pods/*" -not -path "*/build/*" -not -path "*/DerivedData/*" -not -path "*/.build/*" | while read -r xcconfig; do
  sed -i '' -E "s/DEVELOPMENT_TEAM *= *.*/DEVELOPMENT_TEAM = \${team}/" "\$xcconfig"
  sed -i '' -E "s/CODE_SIGN_IDENTITY *= *.*/CODE_SIGN_IDENTITY = Apple Development/" "\$xcconfig"
  sed -i '' -E "s/CODE_SIGN_STYLE *= *.*/CODE_SIGN_STYLE = Automatic/" "\$xcconfig"
  git update-index --assume-unchanged "\$xcconfig" 2>/dev/null || true
done
HOOK
fi

chmod +x "$HOOKS_DIR/post-checkout"
cp "$HOOKS_DIR/post-checkout" "$HOOKS_DIR/post-merge"

# --- Run immediately ---
"$HOOKS_DIR/post-checkout"

# --- Report ---
if [ "$MODE" = "adhoc" ]; then
  echo "Done! Ad-hoc signing configured (no Apple account needed)"
else
  echo "Done! Team ID set to: $team"
  echo ""
  echo "Make sure this team's Apple ID is logged in under Xcode > Settings > Accounts."
fi
