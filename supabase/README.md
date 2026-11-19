# HOH cloud setup (once, about 20–30 minutes)

This gives Zip Receipt real logins, locations and staff phones. You do it **once**. After that, adding a location or a person is a button in Zip Receipt; nobody else touches Supabase.

## 1. Create the Supabase project
1. Go to **supabase.com** and sign up (free).
2. Click **New project**.
   - **Name:** `zip-receipt`
   - **Database password:** click **Generate**, and save it in your password manager. You won't need it day to day.
   - **Region:** the closest to Iraq, for example **Central EU (Frankfurt)**.
3. Click **Create new project** and wait a minute or two while it sets up.

## 2. Create the tables and security rules
1. In the left sidebar, open **SQL Editor**, then click **New query**.
2. Open `setup.sql` from this folder, copy **all** of it, paste it in, and click **Run**.
3. It should say **Success. No rows returned**. If it shows an error, copy it to Claude.

You can run `setup.sql` again later, when Zip Receipt is updated. It only adds what's missing and never deletes data.

## 3. Two login settings
In the sidebar, open **Authentication → Sign In / Providers** (on some versions it's **Authentication → Providers** or **Settings**):
1. **Allow anonymous sign-ins: ON.** This lets staff join from a phone link without an email or password. Their link only works for the person you invited.
2. Open **Email** and turn **Confirm email: OFF.** Bookkeepers and admins can then sign in straight after choosing a password.

## 4. Copy two values
Click **Connect** at the top of the dashboard (or **Project Settings → API Keys / Data API**) and copy:
- the **Project URL**, which looks like `https://abcdxyz.supabase.co`;
- the **Publishable key**, which starts with `sb_publishable_` (older projects call it the **anon public** key).

Never paste the **secret** or **service_role** key anywhere. Zip Receipt doesn't need it.

## 5. Create HOH in Zip Receipt
1. Open Zip Receipt and go to **Settings → HOH cloud**. Click **Create the organisation**.
2. Fill in:
   - the **Project URL** and **Publishable key** from step 4;
   - **Organisation name:** Hands of Hope (HOH);
   - **your name**;
   - **First location:** for example Erbil;
   - **your email and a password.** This is your admin login.
3. Click **Create organisation**. When it asks, choose to **upload** the books already on this computer to Erbil.
4. Still in **Settings**, check the **Phone app address** (your `…github.io/zip-receipt-phone/` link), so invite links open the phone app.

## 6. Add locations and people
In the **People** tab:
- **Add location** for each other place, for example Duhok.
- **Add person** with a name, a role and their location(s). Zip Receipt shows an **invite link**. Send it privately, for example on WhatsApp.
  - **Staff** open it on their phone and they're in. They then add it to the Home Screen.
  - **Bookkeepers, admins and viewers** install Zip Receipt (from your Release page), open **Settings → HOH cloud**, paste the link, choose a password, and click **Join with invite**. The same email and password work on any computer, or on a phone.
- **Lost phone, or someone leaves:** use **New device link** to move a person to a new phone, or **Edit → untick Active** to switch them off.

## Good to know
- **Cost:** the free plan is plenty for HOH's size. Free projects **pause after about a week with no use at all**. Day-to-day use keeps it awake, and if it pauses, log in to supabase.com and click **Restore**. The **Pro** plan (about $25/month) never pauses and adds daily backups.
- **Backups:** every Zip Receipt computer also keeps its own copy in `Documents/Zip_Receipt`, with a backup for each day.
- **Who can see what:** the security rules in `setup.sql` are enforced by the database itself, not just the app:
  - **Staff** only ever see their own advances and expenses.
  - **Bookkeepers** see only their own location(s).
  - **Admins** see everything.
  - **The last admin** can't be removed.
- **Offline:** the apps keep working without internet and catch up when the connection returns.

## Zoho Expense connection (ZIPPY v2.4, about 15 minutes, once)

This lets ZIPPY send each month's safe and personal reports straight into Zoho Expense, with receipts attached. The Zoho sign-in is kept in HOH cloud, never on a computer, so this repository can stay public. QuickBooks gets the expenses from Zoho (step 6).

### 1. Update the database
Open **SQL Editor → New query**, paste all of `setup.sql` again and click **Run**. It adds four Zoho tables and changes nothing else.

### 2. Register ZIPPY with Zoho
1. Go to **api-console.zoho.com**, sign in with the Zoho account that owns HOH's Zoho Expense, and click **Add Client → Server-based Applications**.
2. Fill in:
   - **Client Name:** ZIPPY
   - **Homepage URL:** your GitHub page for ZIPPY (any address works)
   - **Authorized Redirect URIs:** `https://YOUR-PROJECT.supabase.co/functions/v1/zoho/callback` (your Project URL from step 4 above, then `/functions/v1/zoho/callback`)
3. Click **Create**, then copy the **Client ID** and **Client Secret**.
4. If your Zoho Expense address isn't `expense.zoho.com` (for example `expense.zoho.eu`), open the client's **Settings** tab and turn on that data centre.

### 3. Add the cloud function
1. In Supabase, open **Edge Functions → Deploy a new function → Via Editor**.
2. Name it exactly `zoho`. Replace everything in the editor with the contents of `supabase/functions/zoho/index.ts`, then click **Deploy**.
3. Open the function's **Details** (or **Settings**) and turn **Verify JWT** (sometimes "Enforce JWT verification") **OFF**, then save. Zoho's sign-in page returns to this function without a Supabase login; the function checks every ZIPPY login itself.
4. Open **Edge Functions → Secrets** and add two secrets:
   - `ZOHO_CLIENT_ID` = the Client ID from step 2
   - `ZOHO_CLIENT_SECRET` = the Client Secret from step 2

When ZIPPY is updated later, paste the new `index.ts` over the old one and deploy again.

### 4. Connect (an admin, once for everyone)
In ZIPPY: **Reports → Send to Zoho Expense → Connect Zoho**. Your browser opens Zoho: sign in, click **Accept**, close the tab and go back to ZIPPY. It shows **Connected to (your Zoho organisation)**.

### 5. Match categories
**Zoho settings** now suggests the categories from your Zoho organisation. Match every ZIPPY category to one of them: Zoho rejects an expense without a real category, so ZIPPY checks them all before it sends anything. A receipt's **Project** (for example Restoration) goes to the Zoho customer or project with the same name.

### 6. QuickBooks
In Zoho Expense, as an admin: **Settings → Integrations → QuickBooks Online → Connect**. Map Zoho's categories to QuickBooks accounts there. From then on, approved Zoho reports go to QuickBooks through Zoho's own integration; ZIPPY doesn't connect to QuickBooks itself.

### How sending works
- **Send safe report** / **Send personal report** create a **draft** report in Zoho with one expense per line, and attach receipts: official receipts as PDFs (from the Mac and Windows apps) and phone photos (from any version). Lines with a paper shop receipt still need that receipt attached in Zoho.
- You review the draft in Zoho and submit it there.
- **Sending again is safe.** Lines already in Zoho are skipped; new lines join the same report. Once the report is submitted, recall it in Zoho before adding more.
- IQD lines carry the month's exchange rate from the Books tab. If Zoho ever uses its own rate instead, ZIPPY says so after sending.
- Admins and bookkeepers can send (bookkeepers for their own locations). Only admins can connect or disconnect Zoho.
- The CSV buttons still work, for computers without HOH cloud.
