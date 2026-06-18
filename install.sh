#!/bin/sh
set -e

die() { echo "fatal: $*" >&2; exit 1; }

[ -d ".git" ] || die "not a git repository"

team=$1
if [ -z "$team" ]; then
  team=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')
  [ -n "$team" ] || die "no team id found in keychain. usage: $0 [TEAM_ID]"
fi

mkdir -p .git/hooks

cat > .git/hooks/post-checkout << 'EOF'
#!/bin/sh
team="TEAM_ID"
find . -name "project.pbxproj" | while read -r proj; do
  sed -i '' -E "s/DEVELOPMENT_TEAM = [A-Z0-9]{10};/DEVELOPMENT_TEAM = ${team};/g" "$proj"
  sed -i '' -E "s/\"DEVELOPMENT_TEAM\[sdk=macosx\*\]\" = [A-Z0-9]{10};/\"DEVELOPMENT_TEAM[sdk=macosx*]\" = ${team};/g" "$proj"
  git update-index --assume-unchanged "$proj" 2>/dev/null || true
done
find . -name "*.xcconfig" | while read -r xcconfig; do
  sed -i '' -E "s/DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = ${team}/g" "$xcconfig"
  sed -i '' -E "s/CODE_SIGN_IDENTITY = -/CODE_SIGN_IDENTITY = Apple Development/g" "$xcconfig"
  git update-index --assume-unchanged "$xcconfig" 2>/dev/null || true
done
EOF

sed -i '' "s/TEAM_ID/$team/" .git/hooks/post-checkout
chmod +x .git/hooks/post-checkout

.git/hooks/post-checkout

echo "ok"
