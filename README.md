# xcode-team-patcher

If you've ever contributed to an open-source macOS or iOS app, you probably hate dealing with TCC permission popups (Accessibility, Screen Recording, etc.) every time you rebuild the project.

The issue happens because you're using Ad-Hoc signing (`-`). macOS sees a new hash on every build and resets your permissions. The only way around this is signing the app with your own Apple Development certificate. But changing the Team ID in `.pbxproj` is a nightmare because it causes merge conflicts and gets overwritten every time you switch branches or pull upstream changes.

This is a simple git hook that fixes the problem permanently. 

It runs on `post-checkout`, finds any hardcoded Team IDs in the Xcode project, replaces them with yours, and then tells git to ignore the local changes so your PRs stay clean.

## Usage

Go to your cloned repo and run:

```bash
cd your repo
curl -O https://raw.githubusercontent.com/MoonMao42/xcode-team-patcher/main/install.sh
chmod +x install.sh
./install.sh
```

The script will automatically grab your Team ID from your macOS keychain and set up the hook.

## Uninstall

If you ever want to remove it:
```bash
cd your repo
rm .git/hooks/post-checkout
git update-index --no-assume-unchanged *.xcodeproj/project.pbxproj
```
