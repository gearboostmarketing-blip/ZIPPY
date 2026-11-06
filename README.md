# ⚡ Zip Receipt

Offline cash books and official org receipts for Hands of Hope (HOH), built from the cash log.

- **Any computer:** open `index.html` in Chrome or Edge (double-click it). It needs no install and no internet.
- **Phones:** staff log expenses and receipt photos on their phones (iPhone or Android). They go into your Google Sheet, and **Sync phones** pulls them in. See [`google-sheet/README.md`](google-sheet/README.md) and the separate `zip-receipt-phone` repository.
- **Mac app:** saves automatically to `Documents/Zip_Receipt` and writes PDFs directly. GitHub builds a `Zip-Receipt.dmg` installer for you: see [`mac/README.md`](mac/README.md).

## What it does

1. **Import.** Drop in any of these:
   - a Telegram chat export (*Export chat history → HTML*)
   - a WhatsApp `.txt` export
   - a spreadsheet (`.xlsx` or `.csv`). You pick which column is the date, description, amount (or In/Out, or separate IQD/USD columns), who paid, business, category and project. It guesses the columns from the headers and skips "Total" rows.

   You can also paste lines.
2. **Log.** Review every amount. Set each line's type (Expense, Advance, Salary, Money in, Safe count, Skip) and currency (IQD / USD). Yellow rows need a look. **Split** breaks up lines that bundle several purchases.
3. **Books.** Money in and out for IQD and USD, plus a **Total in USD** using the exchange rate you set on the Books tab. That shows money in, money out, ending balance, counted cash and the difference, all in dollars. It also has safe-count checks. Print the report or save it as a PDF.
4. **Receipts.** One official HOH org receipt per expense. Receipts from phones link to their photo. Fill in business, category, project and items, and mark each one reviewed. Then print two per A4 landscape page, or save as a PDF.

## Data

- **Browser version:** work saves inside the browser on that computer. Use **Settings → Save backup file** to keep monthly copies.
- **Mac app:** work saves to `Documents/Zip_Receipt`, with a folder for each month.
- Backups, PDFs, chat exports and spreadsheets hold real financial data. `.gitignore` keeps them out of the repository.

## Signatures

In **Settings → Signatures**, sign with a trackpad, mouse or finger, or upload a photo of a signature on white paper. Save it under the person's name exactly as it appears on receipts. A receipt prints a signature when its **Paid by** or **Verified by** name matches. Untick **Print saved signatures on receipts** to turn this off.

## Changing the receipt

The receipt copies `HOH_Org_Receipt_Template.xlsx`. The header text, statement wording and signer names are in **Settings**. The layout itself is `receiptHTML()` in `index.html`.

`index.html` includes [fflate](https://github.com/101arrowz/fflate) 0.8.2 (MIT licence) to read .xlsx files offline.
