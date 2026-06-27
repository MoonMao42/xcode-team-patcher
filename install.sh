#!/bin/sh
set -e

die() { echo "fatal: $*" >&2; exit 1; }

[ -d ".git" ] || die "not a git repository"

# --- Uninstall ---
if [ "$1" = "--uninstall" ]; then
  rm -f .git/hooks/post-checkout .git/hooks/post-merge
  find . -name "project.pbxproj" -not -path "*/Pods/*" | while read -r file; do
    git update-index --no-assume-unchanged "$file" 2>/dev/null || true
  done
  find . -maxdepth 1 -name "*.xcconfig" | while read -r file; do
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
    read -r choice </dev/tty
    choice=${choice:-1}
    team=$(printf '%s\n' "$certs" | sed -n "${choice}p" | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')
  fi

  [ "$MODE" = "team" ] && [ -z "$team" ] && die "failed to detect team id"
fi

mkdir -p .git/hooks

# --- Generate hook ---
if [ "$MODE" = "adhoc" ]; then
  cat > .git/hooks/post-checkout << 'HOOK'
#!/bin/sh
# xcode-team-patcher: ad-hoc signing (no certificate needed)
find . -name "project.pbxproj" -not -path "*/Pods/*" | while read -r proj; do
  sed -i '' -E 's/DEVELOPMENT_TEAM = [A-Z0-9]{10};/DEVELOPMENT_TEAM = "";/g' "$proj"
  sed -i '' -E 's/"DEVELOPMENT_TEAM\[sdk=macosx\*\]" = [A-Z0-9]{10};/"DEVELOPMENT_TEAM[sdk=macosx*]" = "";/g' "$proj"
  git update-index --assume-unchanged "$proj" 2>/dev/null || true
done
find . -maxdepth 1 -name "*.xcconfig" | while read -r xcconfig; do
  sed -i '' -E "s/DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM =/" "$xcconfig"
  sed -i '' -E "s/CODE_SIGN_IDENTITY = .*/CODE_SIGN_IDENTITY = -/" "$xcconfig"
  sed -i '' -E "s/CODE_SIGN_STYLE = .*/CODE_SIGN_STYLE = Manual/" "$xcconfig"
  git update-index --assume-unchanged "$xcconfig" 2>/dev/null || true
done
HOOK
else
  cat > .git/hooks/post-checkout << HOOK
#!/bin/sh
# xcode-team-patcher: team signing with ${team}
team="${team}"
find . -name "project.pbxproj" -not -path "*/Pods/*" | while read -r proj; do
  sed -i '' -E "s/DEVELOPMENT_TEAM = [A-Z0-9]{10};/DEVELOPMENT_TEAM = \${team};/g" "\$proj"
  sed -i '' -E "s/\"DEVELOPMENT_TEAM\[sdk=macosx\*\]\" = [A-Z0-9]{10};/\"DEVELOPMENT_TEAM[sdk=macosx*]\" = \${team};/g" "\$proj"
  git update-index --assume-unchanged "\$proj" 2>/dev/null || true
done
find . -maxdepth 1 -name "*.xcconfig" | while read -r xcconfig; do
  sed -i '' -E "s/DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = \${team}/" "\$xcconfig"
  sed -i '' -E "s/CODE_SIGN_IDENTITY = .*/CODE_SIGN_IDENTITY = Apple Development/" "\$xcconfig"
  sed -i '' -E "s/CODE_SIGN_STYLE = .*/CODE_SIGN_STYLE = Automatic/" "\$xcconfig"
  git update-index --assume-unchanged "\$xcconfig" 2>/dev/null || true
done
HOOK
fi

chmod +x .git/hooks/post-checkout
cp .git/hooks/post-checkout .git/hooks/post-merge

# --- Run immediately ---
.git/hooks/post-checkout

# --- Report ---
if [ "$MODE" = "adhoc" ]; then
  echo "Done! Ad-hoc signing configured (no Apple account needed)"
else
  echo "Done! Team ID set to: $team"
  echo ""
  echo "Make sure this team's Apple ID is logged in under Xcode > Settings > Accounts."
fi
