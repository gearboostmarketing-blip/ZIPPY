# ⚡ Zip Receipt v1.0

Offline cash books and official org receipts for Hands of Hope (HOH), built from the cash log.

- **Any computer:** open `index.html` in Chrome or Edge (double-click it). It needs no install and no internet.
- **Phones:** staff log expenses and receipt photos on their phones (iPhone or Android). They go into your Google Sheet, and **Sync phones** pulls them in. See [`google-sheet/README.md`](google-sheet/README.md) and the separate `zip-receipt-phone` repository.
- **Mac app:** saves automatically to `Documents/Zip_Receipt` and writes PDFs directly. GitHub builds a `Zip-Receipt.dmg` installer for you: see [`mac/README.md`](mac/README.md).
- **Windows app:** the same, with a `Zip-Receipt-Setup.exe` installer that GitHub builds for you: see [`windows/README.md`](windows/README.md).

## What it does

1. **Import.** Drop in a Telegram chat export (*Export chat history → HTML*), a WhatsApp `.txt` export, or a spreadsheet (`.xlsx` or `.csv`), paste lines, or click **Sync phones**. Every line lands in its month by date. Nothing is ever cleared.
2. **Pick a month** with the switcher at the top of **Log**, **Books** and **Receipts**.
3. **Log.** Review each amount: type (Expense, Advance, Salary, Money in, Safe count, Skip) and currency (IQD / USD). Yellow rows need a look. **Split** breaks up lines that bundle several purchases.
4. **Books.** Everything in US dollars at the month's exchange rate. Each month opens with the balance carried from the month before; after a safe count, it carries the counted cash. The **safe count register** holds every count, from the desk or from phones, and the latest one is the month's actual. The month report exports as **PDF** or **Excel**.
5. **Receipts.** One official HOH org receipt per expense, for the month. Fill in business, category, project and items, mark each one reviewed, then print two per A4 landscape page or save as a PDF.

**Safe count reminder:** in the last three days of a month (and the first five of the next), if no count has been recorded for that month, Zip Receipt and the phone app both show a reminder.

## Data

- **Browser version:** work saves inside the browser on that computer. Use **Settings → Save backup file** now and then to keep a copy.
- **Mac and Windows apps:** work saves to `Documents/Zip_Receipt` (`current.json`, plus a daily copy in `backups/`). Each month's PDFs and Excel report go in a folder for that month.
- Backups, PDFs, chat exports and spreadsheets hold real financial data. `.gitignore` keeps them out of the repository.

## Signatures

In **Settings → Signatures**, sign with a trackpad, mouse or finger, or upload a photo of a signature on white paper. Save it under the person's name exactly as it appears on receipts. A receipt prints a signature when its **Paid by** or **Verified by** name matches. Untick **Print saved signatures on receipts** to turn this off.

## Changing the receipt

The receipt copies `HOH_Org_Receipt_Template.xlsx`. The header text, statement wording and signer names are in **Settings**. The layout itself is `receiptHTML()` in `index.html`.

`index.html` includes [fflate](https://github.com/101arrowz/fflate) 0.8.2 (MIT licence) to read .xlsx files offline.

## Releases

To publish a version, create a tag such as `v1.0` in GitHub Desktop (**History**, right-click the latest commit, **Create Tag**) and push it. GitHub builds both installers and attaches `Zip-Receipt.dmg` and `Zip-Receipt-Setup.exe` to a **Release** you can link staff to.
