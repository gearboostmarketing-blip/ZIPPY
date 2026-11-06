# Google Sheet setup (once, about 10 minutes)

The sheet is where phones send expenses. Zip Receipt's **Sync phones** button reads from it, and receipt photos go into a folder in your Google Drive.

## 1. Make the sheet

1. Go to [sheets.google.com](https://sheets.google.com) and create a blank spreadsheet. Name it **Zip Receipt – Phone Log**.
2. Click **Extensions → Apps Script**. A code editor opens in a new tab.
3. Delete everything in the editor, paste in the whole of `Code.gs` from this folder, and click the **Save** (disk) icon.

## 2. Run the setup

1. In the toolbar, choose **setup** in the function dropdown, then click **Run**.
2. Google asks for permission. Click **Review permissions** and pick your account.
3. Google will say it *hasn't verified this app*. That's normal for your own scripts. Click **Advanced**, then **Go to … (unsafe)**, then **Allow**.
4. At the bottom you'll see **Your access code is: XXXXXXXXXX**. Copy it.

This creates an **Expenses** tab in the sheet and a **Zip Receipt Photos** folder in your Drive.

## 3. Turn it on

1. Click **Deploy → New deployment**.
2. Click the gear next to *Select type* and choose **Web app**.
3. Fill in:
   - **Execute as:** Me
   - **Who has access:** Anyone
4. Click **Deploy** and copy the **Web app URL**. It ends in `/exec`.

"Anyone" means anyone with that link can reach the script, but the script refuses every request without your access code.

## 4. Connect Zip Receipt

1. In Zip Receipt, open **Settings → Phones & Google Sheet**.
2. Paste the **Web app URL** and the **access code**.
3. Click **Test connection**. It should say *Connected ✓*.

## Later

- **You change `Code.gs`:** use **Deploy → Manage deployments**, click the pencil, choose **Version: New version**, then **Deploy**. The URL stays the same.
- **A phone is lost, or someone leaves:** run **newAccessCode**, update the code in Zip Receipt, and send everyone a new phone setup link.
- **Forgot the code:** run **showAccessCode**.
- **The sheet itself:** you can read it, sort it, or download it as Excel any time. Don't rename the **Expenses** tab or reorder its columns. The **Status** column is free for your own notes.
