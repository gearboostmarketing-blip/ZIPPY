# Zip Receipt for Windows

A Windows app that wraps `../index.html` in a window, using Microsoft's built-in Edge engine (WebView2). It does the same things as the Mac app:

- **Saves automatically to `Documents\Zip_Receipt`:** `current.json` holds all your work, with a daily copy in `backups\`. Each month's PDFs and Excel report go in a folder for that month.
- **Save PDF writes the file directly, with no print dialog:** `Documents\Zip_Receipt\<month>\Receipts <month>.pdf` and `Report <month>.pdf`. **Print…** still opens the normal print window.
- **Folder** opens `Documents\Zip_Receipt` in File Explorer.

## Get the installer

GitHub builds it for you; nothing needs to be installed on a Windows PC to build it.

1. Push the repository, or open the **Actions** tab and click **Build Windows app → Run workflow**.
2. When the run shows a green tick (about 5 minutes), click it. Under **Artifacts**, download **Zip-Receipt-Windows**, then unzip it to get `Zip-Receipt-Setup.exe`.
3. Send that file to the Windows computer by USB, Google Drive or WhatsApp.

## Install (each Windows computer, once)

1. Double-click `Zip-Receipt-Setup.exe`.
2. **"Windows protected your PC":** the installer isn't signed with a paid certificate, so Windows warns about it. Click **More info**, then **Run anyway**.
3. Click through the installer. It installs for that Windows user only and needs no administrator password.
4. Zip Receipt opens, and is now in the Start menu (and on the desktop, if you ticked that box).

It needs the **Microsoft Edge WebView2 Runtime**, which is already part of Windows 10 and 11. If the app ever says WebView2 is missing, install it free from Microsoft's website.

## Updating

Push the changes, download the new installer, and run it over the old one. Data in `Documents\Zip_Receipt` is never touched.

## Moving work in

On the old computer, use **Settings → Save backup file**. On the Windows computer, use **Settings → Open backup file**.
