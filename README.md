# ⚡ Zip Receipt v2.1

Offline cash books and official org receipts for Hands of Hope (HOH), built from the cash log.

- **Any computer:** open `index.html` in Chrome or Edge (double-click it). It needs no install and no internet.
- **Phones:** staff log expenses and receipt photos on their phones (iPhone or Android). They go into your Google Sheet, and **Sync phones** pulls them in. See [`google-sheet/README.md`](google-sheet/README.md) and the separate `zip-receipt-phone` repository.
- **Mac app:** saves automatically to `Documents/Zip_Receipt` and writes PDFs directly. GitHub builds a `Zip-Receipt.dmg` installer for you: see [`mac/README.md`](mac/README.md).
- **Windows app:** the same, with a `Zip-Receipt-Setup.exe` installer that GitHub builds for you: see [`windows/README.md`](windows/README.md).

## New in v2: HOH cloud

One organisation, several locations, proper logins. Set up once with [`supabase/README.md`](supabase/README.md).

| Role | Can do |
|---|---|
| **Admin** | Everything: every location, the all-locations report, People, HOH receipt settings. You can have several. |
| **Bookkeeper** | Books, safe counts, receipts, reports and staff advances for their location(s). |
| **Staff** | Phone only: log expenses with photos and see their own advance balance. |
| **Viewer** | Read-only books for chosen locations. |

- **People tab:** add locations and people, choose their role and locations, and send personal invite links. Staff join from a phone link with no password.
- **Advances:** give advances to anyone, as many as needed. Expenses ticked **Reimbursable** (the default on staff phones) come off that person's advance instead of the safe; untick it when they paid with safe cash. When someone has no advance, the balance shows what HOH owes them. **Repayment** records paying them back, or money they return.
- **Reports:** the all-locations table for admins, staff advance balances, and a PDF/Excel statement for each person.
- **Sync:** every computer and phone syncs automatically and keeps working offline. The location switcher sits at the top of the window.

Without the cloud, Zip Receipt still works on its own as before.

## What it does

1. **Import.** Drop in a Telegram chat export (*Export chat history → HTML*), a WhatsApp `.txt` export, or a spreadsheet (`.xlsx` or `.csv`), paste lines, or click **Sync phones**. Every line lands in its month by date. Nothing is ever cleared.
2. **Pick a month** with the switcher at the top of **Log**, **Books** and **Receipts**.
3. **Log.** Review each amount: type (Expense, Advance, Salary, Money in, Safe count, Skip) and currency (IQD / USD). Yellow rows need a look. **Split** breaks up lines that bundle several purchases.
4. **Books.** Everything in US dollars at the month's exchange rate. Each month opens with the balance carried from the month before; after a safe count, it carries the counted cash. The **safe count register** holds every count, from the desk or from phones, and the latest one is the month's actual. The month report exports as **PDF** or **Excel**.
5. **Receipts.** One official HOH org receipt per expense, for the month. **Safe** and **Personal** receipts are kept apart. Fill in business, category, project and items, mark each one reviewed, then print two per A4 landscape page or save as a PDF.

**Advances and reimbursables:** an advance from the safe counts as money out of the safe. Tick **Mine** on your own advances (it's guessed from your name in **Settings → My name**). Tick **Reimb.** on expenses you paid from your advance or your own pocket, in the Log or on the phone. Those come off your advance, not the safe. The **My ledger** tab shows the balance month by month: advance money you still hold, or what HOH owes you.

**Reports tab:** everything for the month (safe books, safe receipts, my ledger, personal receipts, the full log) as PDF or Excel, with **Save all** on Mac and Windows. It also has the safe count register month by month, and **Copy for Telegram**: this week's, last week's or the month's expenses in the import line format.

**Log export:** the Log tab exports what's shown (pick a source such as your Telegram chat) as Excel, for this month or all months.

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

## Releases and automatic updates

**Publishing a new version**
1. Push your changes.
2. In GitHub Desktop, go to **History**, right-click the latest commit, choose **Create Tag**, type the new version (for example `v2.2`), and click **Push origin**.
3. GitHub builds the Mac and Windows installers with that version number and puts them on a **Release**, along with `index.html`.
4. Optional: open the Release on github.com and write what changed. The apps show this text under **What's new**.

**How the apps update:** when Zip Receipt opens (and twice a day after that), it checks the latest Release. If it's newer, a banner offers **Update now**. The Mac and Windows apps download the new version, install it over the old one, and reopen by themselves. Data in `Documents/Zip_Receipt` is never touched. The browser version shows a **Download** button instead.

**One-time requirements**
- **Make this repository public** (github.com → repository **Settings → General → Danger Zone → Change visibility → Public**). GitHub only lets apps download releases from public repositories. It contains only the app's code: data, names, keys and passwords are never stored here.
- **Install v2.1 by hand once** (it's the first version with the updater). After that, updates are one click.
- **Mac:** keep Zip Receipt in your **Applications** folder, so it can replace itself.

**Checking manually:** **Settings → Updates → Check for updates**.
