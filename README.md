# ⚡ Zip Receipt

Offline cash books and official org receipts for Hands of Hope (HOH), built from the cash log.

- **Any computer:** open `index.html` in Chrome or Edge (double-click it). It needs no install and no internet.
- **Mac app:** saves automatically to `Documents/Zip_Receipt` and writes PDFs directly. GitHub builds a `Zip-Receipt.dmg` installer for you: see [`mac/README.md`](mac/README.md).

## What it does

1. **Import.** Drop in any of these:
   - a Telegram chat export (*Export chat history → HTML*)
   - a WhatsApp `.txt` export
   - a spreadsheet (`.xlsx` or `.csv`). You pick which column is the date, description, amount (or In/Out, or separate IQD/USD columns), who paid, business, category and project. It guesses the columns from the headers and skips "Total" rows.

   You can also paste lines.
2. **Log.** Review every amount. Set each line's type (Expense, Advance, Salary, Money in, Safe count, Skip) and currency (IQD / USD). Yellow rows need a look. **Split** breaks up lines that bundle several purchases.
3. **Books.** Money in and out per currency, with opening balance, counted cash and the difference, plus safe-count checks. Print the report or save it as a PDF.
4. **Receipts.** One official HOH org receipt per expense. Fill in business, category, project and items, and mark each one reviewed. Then print two per A4 landscape page, or save as a PDF.

## Data

- **Browser version:** work saves inside the browser on that computer. Use **Settings → Save backup file** to keep monthly copies.
- **Mac app:** work saves to `Documents/Zip_Receipt`, with a folder for each month.
- Backups, PDFs, chat exports and spreadsheets hold real financial data. `.gitignore` keeps them out of the repository.

## Changing the receipt

The receipt copies `HOH_Org_Receipt_Template.xlsx`. The header text, statement wording and signer names are in **Settings**. The layout itself is `receiptHTML()` in `index.html`.

`index.html` includes [fflate](https://github.com/101arrowz/fflate) 0.8.2 (MIT licence) to read .xlsx files offline.
