# Zip Receipt for Mac

A small native Mac app that wraps `../index.html` in a window. It does the same things as the browser version, plus:

- **Saves automatically to `Documents/Zip_Receipt`.** `current.json` holds all your work, with a daily copy in `backups/`. Each month's PDFs and Excel report go in a folder for that month.
- **Save PDF writes the file directly, with no print dialog.** Files go to `Documents/Zip_Receipt/<month>/Receipts <month>.pdf` and `Report <month>.pdf`. The **Print…** button still opens the normal print window.
- It has a **Folder** button, and **File → Open Zip_Receipt Folder** (⌘O).

## Easiest: download the DMG from GitHub

GitHub builds the installer for you on one of its own Macs, so you don't need any developer tools.

1. Publish the repository with GitHub Desktop. Keep it **private**.
2. On github.com, open the repository and go to the **Actions** tab. A run called **Build Mac app** starts after each push that changes the app. You can also start one yourself: **Build Mac app → Run workflow**.
3. When it shows a green tick (after about 3 minutes), click the run. Under **Artifacts**, download **Zip-Receipt-dmg**. It downloads as a zip; unzip it to get `Zip-Receipt.dmg`.
4. Open the DMG and drag **Zip Receipt** onto **Applications**.
5. **The first time you open it, macOS blocks it.** The app isn't signed with a paid Apple developer account, so macOS can't verify where it came from.
   - Click **Done**, then go to **System Settings → Privacy & Security**.
   - Scroll down and click **Open Anyway** next to Zip Receipt, then confirm.
   - You only do this once per Mac.

If a build fails, the run shows a red ✕. Click into it, open the **Build app and DMG** step, and copy the error text.

## Or build it on your own Mac

1. Install Apple's command-line tools by running this in Terminal (it's free, and you don't need full Xcode):
   ```
   xcode-select --install
   ```
2. In Terminal, go to this folder and build. Drag the `mac` folder onto the Terminal window after typing `cd ` to fill in the path:
   ```
   cd ~/Documents/GitHub/zip-receipt/mac
   ./build.sh --install
   ```
3. Zip Receipt opens and is now in **Applications**. Drag it to the Dock if you like.

The first time it saves, macOS asks to let Zip Receipt access the Documents folder. Click **Allow**.

## Updating

When `index.html` or `ZipReceipt.swift` changes, run `./build.sh --install` again. Your data is safe, because it lives in `Documents/Zip_Receipt`, not inside the app.

## Moving work from the browser version

In the browser version, use **Settings → Save backup file**. In the Mac app, use **Settings → Open backup file**.

## Native bridge (shared with the Windows app)

`index.html` checks for `window.webkit.messageHandlers.zip` (Mac) or `window.zipNative` (any other shell). Each call is `native({cmd, ...})` and returns a Promise. The Windows app (`windows/Program.cs`, C# + WebView2) implements the same seven commands:

| cmd | fields | returns |
|---|---|---|
| `info` | – | `{folder, platform}` |
| `read` | `path` | file text, or null if the file doesn't exist |
| `write` | `path`, `text`, `base64` (optional) | the full path written; with `base64: true`, `text` is base64 and is saved as a binary file (the Excel report) |
| `pdf` | `path`, `landscape` | the full path; prints the page's print layout straight to a PDF |
| `print` | `landscape` | `true`; shows the system print dialog |
| `reveal` | `path` (optional) | `true`; shows the file or folder in Finder / Explorer |
| `http` | `url`, `body` (optional) | response text; fallback for reaching the Google Sheet |

Every `path` is relative to `Documents/Zip_Receipt` and must not contain `..`. Errors reject the Promise. A cancelled print rejects with a message containing "cancelled".
