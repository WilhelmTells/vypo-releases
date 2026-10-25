# vypo

Dictation for your Mac: hold fn, speak, let go, and the text appears wherever your cursor is. Speech recognition runs on your Mac – your voice and your text never leave it.

**Download:** [latest vypo.dmg](https://github.com/WilhelmTells/vypo-releases/releases/latest/download/vypo.dmg) · More at [wilhelmtells.com/vypo](https://wilhelmtells.com/vypo)

This repository holds vypo's releases and its update feed.

## Install

vypo needs an Apple silicon Mac with macOS 26 or later.

1. Open `vypo.dmg` and drag **vypo** into **Applications**.
2. vypo is not notarized by Apple, so macOS blocks the first start. Either:
   - **Way 1:** open vypo, close the warning, then open System Settings → Privacy & Security and click **Open Anyway** next to vypo.
   - **Way 2 (Terminal):** run `xattr -dr com.apple.quarantine /Applications/vypo.app`, then open vypo as usual. This only removes the download mark from vypo itself.
3. On first start vypo asks for Microphone and Accessibility and downloads its speech model (about 0.6 GB, once).

Once installed, vypo checks once a day for a new version and updates itself after you confirm (Settings → About → Check Now looks right away).

## Feedback

In vypo: menu bar icon → Settings… → About → **Send Feedback…** (a mail with only the versions of vypo and macOS) or **Copy Diagnostics…** (a report without any dictated text, to paste into the mail).
