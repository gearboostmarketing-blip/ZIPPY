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
