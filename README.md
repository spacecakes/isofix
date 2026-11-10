<img src="Resources/AppIcon-preview.png" width="128" alt="ISOFix icon">

# ISOFix

Keeps **`§`** and **`<`** where they belong on third-party and custom ISO keyboards on macOS.

## The problem

Apple's ISO keyboards send these two keys the opposite way from the USB standard. So for every other ISO keyboard, macOS has to guess whether to swap them. It often guesses wrong (even after Keyboard Setup Assistant), and even when it gets it right, macOS tends to flip it back later. You end up with `§` next to Shift and `<` under Esc. Maddening!

The usual fix is Karabiner-Elements (terrific app), but it's huge overkill for this simple issue: a driver extension and background services grabbing every keystroke you type and sending it back out through a virtual keyboard, all to swap two keys. That's extra silly on custom keyboards, which are often programmable and already do their own remapping. And a fixed remap can't solve this, whether it's Karabiner or your keyboard's firmware: it swaps blindly, so it's wrong whenever macOS happens to get it right.

Instead, ISOFix notices when `§` and `<` come out wrong and fixes it for that keyboard. It uses macOS's built-in per-keyboard key remapping (the one `hidutil` uses), with no driver, no root, and no interception of your typing.

## Install

Needs macOS 13+ on Apple silicon. Grant **Input Monitoring** when asked. ISOFix uses it to check what `§` and `<` produce. It has no network access and doesn't store anything you type.

If you're running Karabiner-Elements, quit it. It takes over your keyboards, so ISOFix can't fix them.

> [!NOTE]
> Since I'm too cheap to pay for a $99/year Apple developer membership for a little utility I only use myself, this app is not signed by Apple, so macOS blocks it the first time it opens. Go to **System Settings → Privacy & Security** and click **Open Anyway**. Needs redoing after each update. Maybe if people start using it, I'll get it properly notarized.

### Homebrew

```sh
brew install --cask spacecakes/tap/isofix
```

### Download

Download [ISOFix.zip](https://github.com/spacecakes/isofix/releases/latest/download/ISOFix.zip) from the [latest release](https://github.com/spacecakes/isofix/releases/latest), unzip it, and move **ISOFix.app** to **Applications**.

### Build from source

Needs the Xcode Command Line Tools.

```sh
git clone https://github.com/spacecakes/isofix.git && cd isofix && ./build.sh install
```

To keep the Input Monitoring grant across rebuilds, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Usage

Start the app. It runs hidden and starts itself at login. Open it again any time to change its settings.

The first time you press `§` or `<` on a keyboard, it may come out wrong. ISOFix fixes that keyboard from then on.
