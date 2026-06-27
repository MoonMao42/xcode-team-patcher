# xcode-team-patcher

If you've ever contributed to an open-source macOS or iOS app, you probably hate dealing with TCC permission popups (Accessibility, Screen Recording, etc.) every time you rebuild the project.

The issue happens because you're using Ad-Hoc signing (`-`). macOS sees a new hash on every build and resets your permissions. The only way around this is signing the app with your own Apple Development certificate. But changing the Team ID in `.pbxproj` is a nightmare because it causes merge conflicts and gets overwritten every time you switch branches or pull upstream changes.

This is a simple git hook that fixes the problem permanently.

It runs on `post-checkout` and `post-merge`, finds any hardcoded Team IDs in the Xcode project, replaces them with yours, sets up Automatic signing so Xcode can manage provisioning profiles, and then tells git to ignore the local changes so your PRs stay clean.

## Usage

Go to your cloned repo and run:

```bash
curl -O https://raw.githubusercontent.com/MoonMao42/xcode-team-patcher/main/install.sh
chmod +x install.sh && ./install.sh
```

The script will automatically grab your Team ID from your macOS keychain and set up the hook.

If you have **multiple Apple Development certificates**, the script will list them and let you choose which one to use.

You can also pass a Team ID explicitly:

```bash
./install.sh YOUR_TEAM_ID
```

### Ad-hoc mode

If you don't have an Apple Developer account, or you just want the project to compile without any signing setup:

```bash
./install.sh --adhoc
```

This clears all Team IDs and uses ad-hoc signing (`CODE_SIGN_IDENTITY = -`). No certificate, no account, no provisioning profile needed. The tradeoff is that macOS will reset TCC permissions on every rebuild.

## What it patches

In **team mode** (default):
- `DEVELOPMENT_TEAM` → your Team ID (in both `.pbxproj` and `.xcconfig`)
- `CODE_SIGN_IDENTITY` → `Apple Development`
- `CODE_SIGN_STYLE` → `Automatic` (so Xcode auto-manages provisioning profiles)

In **ad-hoc mode** (`--adhoc`):
- `DEVELOPMENT_TEAM` → empty
- `CODE_SIGN_IDENTITY` → `-`
- `CODE_SIGN_STYLE` → `Manual`

All patched files are marked with `git update-index --assume-unchanged` so they won't show up in `git status` or accidentally get committed.

## Uninstall

```bash
./install.sh --uninstall
rm install.sh
```
