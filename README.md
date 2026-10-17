# BlockDock

Requires macOS 13 or later on Apple Silicon or Intel. Building requires Swift 5.9 or later and Xcode command-line tools. The build produces a universal binary; runtime checks were performed on Apple Silicon.

From source: `./build.sh` creates `dist/BlockDock.app`, `dist/BlockDock-macOS.zip`, and `dist/BlockDock-source.zip`.

Run: open `BlockDock.app` beside this README in the prebuilt download, or `dist/BlockDock.app` after building from source. Choose a category and duration. Drag the floating badge to move it; use **Open** or the menu bar clock to return to the dashboard. At expiry, choose **Continue**, switch categories, or **Stop for now**. Finished blocks are saved in `~/Library/Application Support/BlockDock/blocks.json`; daily totals include those blocks and elapsed time from the current block.

The app is locally signed and is not notarized. macOS may block a downloaded copy. To open a copy you trust, first try opening it, then use **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445). Building from source is another option.

From source, test with `swift test`. Synthetic demo: `dist/BlockDock.app/Contents/MacOS/BlockDock --demo --data-dir /tmp/blockdock-demo`. In the prebuilt download, omit `dist/` from that command. Use `--demo-expired` with a fresh data directory to show the expiry decision. Add `--render-demo /tmp/blockdock-demo.png` to save dashboard and badge PNGs (`/tmp/blockdock-demo-badge.png`); the destination folder must exist. Rendering refuses existing output files and app-data paths. Choose new output names to render again. Delete the demo directory to reseed it.

Expand **Completed blocks** to see recent history, or **Edit categories** to change the category list.

Limitations: Time is based on the system clock. A running block ends at its planned deadline even if the app is closed or the Mac sleeps. The app does not infer activity while it is closed. Category names in past history remain as recorded when a category is removed. Use one instance per data directory; the local JSON file is not synced across devices. The history section shows the latest 20 blocks; all history remains in the data file.
