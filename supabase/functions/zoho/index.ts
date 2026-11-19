// ZIPPY ↔ Zoho Expense, running in HOH cloud (Supabase Edge Function "zoho").
// The Zoho login lives only here: ZIPPY computers ask this function to connect, look things up,
// send a month's report and attach receipts. Deploy with "Verify JWT" OFF: Zoho's sign-in page
// returns to /callback without a Supabase login, so this file checks the login itself.
//
// Secrets (Supabase → Edge Functions → Secrets): ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

const SB_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const ZID = Deno.env.get("ZOHO_CLIENT_ID") ?? "";
const ZSECRET = Deno.env.get("ZOHO_CLIENT_SECRET") ?? "";
const REDIRECT = `${SB_URL}/functions/v1/zoho/callback`;
const SCOPE = "ZohoExpense.fullaccess.ALL";
const ACCOUNTS_RE = /^https:\/\/accounts\.zoho\.(com|eu|in|com\.au|jp|ca|com\.cn|sa|uk)$/;
const API_RE = /^https:\/\/www\.zohoapis\.(com|eu|in|com\.au|jp|ca|com\.cn|sa|uk)$/;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
class Fail extends Error { constructor(msg: string, public status = 400) { super(msg); } }

// ---------- database (service role; RLS keeps the app out of these tables) ----------
async function db(method: string, path: string, body?: unknown, prefer?: string) {
  const h: Record<string, string> = { apikey: SRK, Authorization: `Bearer ${SRK}` };
  if (body !== undefined) h["Content-Type"] = "application/json";
  if (prefer) h.Prefer = prefer;
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
  const t = await r.text();
  if (!r.ok) throw new Fail(`Database: ${t.slice(0, 300)}`, 500);
  return t ? JSON.parse(t) : null;
}
const eq = (v: string) => `eq.${encodeURIComponent(v)}`;

// ---------- who is calling? ----------
type Member = { id: string; org_id: string; role: string; name: string };
async function caller(req: Request): Promise<Member> {
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer .+/.test(auth)) throw new Fail("Sign in to HOH cloud first.", 401);
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!r.ok) throw new Fail("Your HOH cloud login has expired. Sign in again.", 401);
  const user = await r.json();
  const rows = await db("GET", `members?select=id,org_id,role,name&active=eq.true&user_id=${eq(user.id)}`);
  if (!rows?.length) throw new Fail("This login isn't an active HOH member.", 403);
  return rows[0];
}
async function needBooks(m: Member, locationId: string) {
  if (m.role === "admin") return;
  if (m.role !== "bookkeeper") throw new Fail("Only admins and bookkeepers can send to Zoho.", 403);
  const ok = await db("GET", `member_locations?select=location_id&member_id=${eq(m.id)}&location_id=${eq(locationId)}`);
  if (!ok?.length) throw new Fail("You don't keep the books for this location.", 403);
}
const needAdmin = (m: Member) => { if (m.role !== "admin") throw new Fail("Only an admin can connect or disconnect Zoho.", 403); };

// ---------- Zoho ----------
type Conn = { org_id: string; refresh_token: string; access_token: string | null; access_expires: string | null;
  accounts_server: string; api_domain: string; zoho_org_id: string | null; zoho_org_name: string | null };

async function getConn(orgId: string): Promise<Conn> {
  const rows = await db("GET", `zoho_connection?select=*&org_id=${eq(orgId)}`);
  if (!rows?.length) throw new Fail("Zoho isn't connected yet. An admin can connect it in Reports → Send to Zoho Expense.", 409);
  return rows[0];
}
async function tokenFor(c: Conn): Promise<string> {
  if (c.access_token && c.access_expires && new Date(c.access_expires).getTime() > Date.now() + 60_000) return c.access_token;
  const q = new URLSearchParams({ refresh_token: c.refresh_token, client_id: ZID, client_secret: ZSECRET, grant_type: "refresh_token" });
  const r = await fetch(`${c.accounts_server}/oauth/v2/token?${q}`, { method: "POST" });
  const d = await r.json().catch(() => ({}));
  if (!d.access_token) throw new Fail(`Zoho sign-in has expired (${d.error ?? r.status}). An admin needs to connect Zoho again.`, 409);
  c.access_token = d.access_token;
  // Zoho gives expires_in in milliseconds on some data centres and seconds on others
  const raw = Number(d.expires_in_sec) || Number(d.expires_in) || 3600, secs = raw > 100000 ? raw / 1000 : raw;
  c.access_expires = new Date(Date.now() + secs * 1000).toISOString();
  await db("PATCH", `zoho_connection?org_id=${eq(c.org_id)}`, { access_token: c.access_token, access_expires: c.access_expires }, "return=minimal");
  return c.access_token!;
}
class ZohoError extends Error { constructor(msg: string, public code: number, public status: number) { super(msg); } }
async function zoho(c: Conn, method: string, path: string, body?: unknown, form?: FormData, retried = false): Promise<any> {
  const h: Record<string, string> = { Authorization: `Zoho-oauthtoken ${await tokenFor(c)}` };
  if (c.zoho_org_id) h["X-com-zoho-expense-organizationid"] = c.zoho_org_id;
  if (body !== undefined) h["Content-Type"] = "application/json";
  const r = await fetch(`${c.api_domain}/expense/v1${path}`, { method, headers: h, body: form ?? (body === undefined ? undefined : JSON.stringify(body)) });
  const d = await r.json().catch(() => ({}));
  if (r.status === 429 && !retried) { await new Promise((s) => setTimeout(s, 4000)); return zoho(c, method, path, body, form, true); }
  if (r.status === 401 && !retried) { c.access_token = null; return zoho(c, method, path, body, form, true); }
  if (!r.ok || (d.code !== undefined && d.code !== 0)) throw new ZohoError(d.message ?? `Zoho error ${r.status}`, d.code ?? -1, r.status);
  return d;
}
async function listAll(c: Conn, path: string, key: string[]): Promise<any[]> {
  const out: any[] = [];
  for (let page = 1; page <= 10; page++) {
    const d = await zoho(c, "GET", `${path}${path.includes("?") ? "&" : "?"}page=${page}&per_page=200`);
    const arr = key.map((k) => d[k]).find(Array.isArray) ?? [];
    out.push(...arr);
    if (!d.page_context?.has_more_page) break;
  }
  return out;
}
const norm = (s: unknown) => String(s ?? "").trim().toLowerCase();

async function lookups(c: Conn) {
  const warnings: string[] = [];
  const safe = async (label: string, f: () => Promise<any[]>) => { try { return await f(); } catch (e) { warnings.push(`Couldn't read ${label} from Zoho (${(e as Error).message}).`); return []; } };
  const cats = (await safe("categories", () => listAll(c, "/expensecategories", ["expense_categories", "categories"])))
    .filter((x) => x.is_enabled !== false && x.status !== "inactive").map((x) => ({ id: String(x.category_id), name: String(x.category_name) }));
  let curs = await safe("currencies", () => listAll(c, "/settings/currencies", ["currencies"]));
  if (!curs.length) curs = await safe("currencies", () => listAll(c, "/currencies", ["currencies"]));
  const currencies = curs.map((x) => ({ id: String(x.currency_id), code: String(x.currency_code) }));
  const customers = (await safe("customers", () => listAll(c, "/customers", ["customers", "contacts"])))
    .map((x) => ({ id: String(x.customer_id ?? x.contact_id), name: String(x.customer_name ?? x.contact_name ?? x.display_name ?? "") }));
  const projects = (await safe("projects", () => listAll(c, "/projects", ["projects"])))
    .map((x) => ({ id: String(x.project_id), name: String(x.project_name) }));
  return { cats, currencies, customers, projects, warnings };
}

// ---------- actions ----------
type Line = { id: string; date: string; currency: string; amount: number; rate: number; desc: string;
  category: string; merchant: string; project: string; reimb: boolean; ref: string };

async function send(m: Member, b: any) {
  const loc = String(b.location_id ?? ""), month = String(b.month ?? ""), grp = b.group === "personal" ? "personal" : "safe";
  if (!/^[0-9a-f-]{36}$/.test(loc) || !/^\d{4}-\d{2}$/.test(month)) throw new Fail("Missing location or month.");
  await needBooks(m, loc);
  const lines: Line[] = Array.isArray(b.lines) ? b.lines : [];
  if (!lines.length) throw new Fail("Nothing to send for this month.");
  if (lines.length > 300) throw new Fail("Too many lines in one send (300 at most).");
  const rep = b.report ?? {};
  const c = await getConn(m.org_id);
  const L = await lookups(c);
  const byName = <T extends { name: string }>(list: T[], name: string) => list.find((x) => norm(x.name) === norm(name));

  // 1. Check everything first, so a send never stops halfway because of a missing category
  const problems: string[] = [], warnings = [...L.warnings];
  const resolved = lines.map((l) => {
    const cur = L.currencies.find((x) => norm(x.code) === norm(l.currency));
    const cat = l.category ? byName(L.cats, l.category) : undefined;
    if (!cur) problems.push(`${l.currency} isn't a currency in your Zoho organisation (Zoho → Settings → Currencies).`);
    if (!l.category) problems.push(`${l.ref} “${l.desc}” has no category.`);
    else if (!cat) problems.push(`Category “${l.category}” (${l.ref}) doesn't match any Zoho category.`);
    const cust = l.project ? byName(L.customers, l.project) : undefined, proj = l.project && !cust ? byName(L.projects, l.project) : undefined;
    if (l.project && !cust && !proj) warnings.push(`“${l.project}” isn't a Zoho customer or project, so ${l.ref} goes without it.`);
    return { l, cur, cat, cust, proj };
  });
  const uniq = [...new Set(problems)];
  if (uniq.length) return { ok: false, problems: uniq, categories: L.cats.map((x) => x.name) };

  // 2. The month's report (reuse it if it's still there)
  const ids = lines.map((l) => String(l.id));
  const inList = `(${ids.map((i) => `"${i.replace(/["\\]/g, "")}"`).join(",")})`;
  const linked: any[] = await db("GET", `zoho_links?select=entry_id,expense_id,has_receipt&org_id=${eq(m.org_id)}&entry_id=in.${encodeURIComponent(inList)}`);
  const linkMap = new Map(linked.map((x) => [x.entry_id, x]));
  const todo = resolved.filter((r) => !linkMap.has(String(r.l.id)));
  const repKey = `org_id=${eq(m.org_id)}&location_id=${eq(loc)}&month=${eq(month)}&grp=${eq(grp)}`;
  let reportId: string | null = null, reportName = String(rep.name ?? `${month} ${grp}`);
  const known = await db("GET", `zoho_reports?select=report_id,report_name&${repKey}`);
  if (known?.length) {
    try { const d = await zoho(c, "GET", `/expensereports/${known[0].report_id}`); reportId = known[0].report_id;
      const st = norm(d.expense_report?.status);
      if (todo.length && st && !["draft", "rejected", "recalled"].includes(st))
        return { ok: false, problems: [`The Zoho report “${known[0].report_name}” is already ${st}. Recall it in Zoho to add the ${todo.length} new line(s), then send again.`] };
    } catch { reportId = null; } // deleted in Zoho: make a new one
  }
  if (!reportId && todo.length) {
    const d = await zoho(c, "POST", "/expensereports", { report_name: reportName, start_date: rep.start, end_date: rep.end, description: rep.purpose || undefined });
    reportId = String(d.expense_report.report_id);
    await db("POST", "zoho_reports?on_conflict=org_id,location_id,month,grp", { org_id: m.org_id, location_id: loc, month, grp, report_id: reportId, report_name: reportName }, "resolution=merge-duplicates,return=minimal");
  }

  // 3. One Zoho expense per new line, straight into the report
  const created: { id: string; expense_id: string }[] = [];
  let extrasOk = true;
  for (const r of todo) {
    const l = r.l;
    const base: Record<string, unknown> = {
      date: l.date, currency_id: r.cur!.id, is_reimbursable: !!l.reimb, report_id: reportId,
      ...(r.cust ? { customer_id: r.cust.id } : {}), ...(r.proj ? { project_id: r.proj.id } : {}),
      line_items: [{ category_id: r.cat!.id, amount: Math.abs(Number(l.amount)), description: [l.desc, l.merchant && `(${l.merchant})`].filter(Boolean).join(" ") }],
    };
    // Not in Zoho's published list, but accepted by Zoho's finance apps: the month's exchange rate, merchant and ZIPPY's reference.
    const extras = { exchange_rate: l.currency === "USD" ? 1 : Number(l.rate), merchant_name: l.merchant || undefined, reference_number: l.ref };
    let d: any;
    try { d = await zoho(c, "POST", "/expenses", extrasOk ? { ...base, ...extras } : base); }
    catch (e) {
      if (!extrasOk || !(e instanceof ZohoError) || e.status >= 500) throw e;
      extrasOk = false; warnings.push(`Zoho wouldn't take the exchange rate or reference number on expenses (${e.message}). Lines went in with Zoho's own exchange rate: check IQD amounts in the report.`);
      d = await zoho(c, "POST", "/expenses", base);
    }
    const exp = (d.expenses ?? [d.expense])[0];
    const eid = String(exp.expense_id);
    if (extrasOk && l.currency !== "USD" && exp.exchange_rate && Math.abs(Number(exp.exchange_rate) - Number(l.rate)) / Number(l.rate) > 0.001)
      warnings.push(`${l.ref}: Zoho used exchange rate ${exp.exchange_rate} instead of ZIPPY's ${Number(l.rate).toPrecision(6)}.`);
    await db("POST", "zoho_links?on_conflict=org_id,entry_id", { org_id: m.org_id, entry_id: String(l.id), expense_id: eid, report_id: reportId }, "resolution=merge-duplicates,return=minimal");
    created.push({ id: String(l.id), expense_id: eid });
  }
  const status: Record<string, { expense_id: string; has_receipt: boolean }> = {};
  linked.forEach((x) => status[x.entry_id] = { expense_id: x.expense_id, has_receipt: x.has_receipt });
  created.forEach((x) => status[x.id] = { expense_id: x.expense_id, has_receipt: false });
  return { ok: true, report_id: reportId, report_name: reportName, created: created.length, already: linked.length, warnings: [...new Set(warnings)], lines: status };
}

async function attach(m: Member, b: any) {
  const entry = String(b.entry_id ?? ""), loc = String(b.location_id ?? "");
  await needBooks(m, loc);
  const rows = await db("GET", `zoho_links?select=expense_id,has_receipt&org_id=${eq(m.org_id)}&entry_id=${eq(entry)}`);
  if (!rows?.length) throw new Fail("Send this line to Zoho before attaching its receipt.");
  if (rows[0].has_receipt && !b.force) return { ok: true, skipped: true };
  let blob: Blob, name: string;
  if (b.photo_path) {
    const p = String(b.photo_path);
    if (!p.startsWith(`${m.org_id}/${loc}/`) || p.includes("..")) throw new Fail("That photo isn't in this location.", 403);
    const r = await fetch(`${SB_URL}/storage/v1/object/receipts/${p.split("/").map(encodeURIComponent).join("/")}`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
    if (!r.ok) throw new Fail("Couldn't read the phone photo from HOH cloud.");
    blob = await r.blob(); name = String(b.filename || p.split("/").pop() || "receipt.jpg");
  } else {
    const mime = String(b.mime || "application/pdf");
    if (!/^(application\/pdf|image\/(jpeg|png))$/.test(mime)) throw new Fail("Receipts must be PDF, JPG or PNG.");
    const bytes = Uint8Array.from(atob(String(b.data ?? "")), (ch) => ch.charCodeAt(0));
    if (!bytes.length || bytes.length > 10_000_000) throw new Fail("Receipt file is empty or too big.");
    blob = new Blob([bytes], { type: mime }); name = String(b.filename || "receipt.pdf");
  }
  const c = await getConn(m.org_id);
  const f = new FormData(); f.append("attachment", blob, name.replace(/[\\/:*?"<>|]+/g, " ").slice(0, 100));
  await zoho(c, "POST", `/expenses/${rows[0].expense_id}/documents`, undefined, f);
  await db("PATCH", `zoho_links?org_id=${eq(m.org_id)}&entry_id=${eq(entry)}`, { has_receipt: true }, "return=minimal");
  return { ok: true };
}

async function callback(url: URL) {
  const page = (title: string, msg: string) => new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>` +
    `<body style="font:16px/1.5 system-ui,sans-serif;max-width:460px;margin:15vh auto;padding:0 20px;color:#37352f">` +
    `<div style="font-size:28px">⚡</div><h1 style="font-size:22px;margin:8px 0">${title}</h1><p>${msg}</p></body>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } });
  const err = url.searchParams.get("error");
  if (err) return page("Zoho wasn't connected", `Zoho said: ${err.replace(/[<>&]/g, "")}. Close this tab and try again from ZIPPY.`);
  const code = url.searchParams.get("code") ?? "", state = url.searchParams.get("state") ?? "";
  const st = await db("GET", `zoho_oauth_state?select=*&state=${eq(state)}`);
  await db("DELETE", `zoho_oauth_state?state=${eq(state)}`, undefined, "return=minimal");
  if (!st?.length || Date.now() - new Date(st[0].created_at).getTime() > 30 * 60_000)
    return page("This link has expired", "Close this tab and click Connect Zoho in ZIPPY again.");
  const accounts = (url.searchParams.get("accounts-server") ?? "https://accounts.zoho.com").replace(/\/$/, "");
  if (!ACCOUNTS_RE.test(accounts)) return page("Unexpected Zoho address", "Close this tab and try again.");
  const q = new URLSearchParams({ code, client_id: ZID, client_secret: ZSECRET, redirect_uri: REDIRECT, grant_type: "authorization_code" });
  const r = await fetch(`${accounts}/oauth/v2/token?${q}`, { method: "POST" });
  const t = await r.json().catch(() => ({}));
  if (!t.refresh_token) return page("Zoho wasn't connected", `Zoho didn't give a lasting sign-in (${t.error ?? r.status}). Close this tab and try again.`);
  const api = String(t.api_domain ?? "https://www.zohoapis.com").replace(/\/$/, "");
  if (!API_RE.test(api)) return page("Unexpected Zoho address", "Close this tab and try again.");
  const conn: Conn = { org_id: st[0].org_id, refresh_token: t.refresh_token, access_token: t.access_token,
    access_expires: new Date(Date.now() + 3500_000).toISOString(), accounts_server: accounts, api_domain: api, zoho_org_id: null, zoho_org_name: null };
  try {
    const d = await zoho(conn, "GET", "/organizations");
    const orgs: any[] = d.organizations ?? [];
    const o = orgs.find((x) => x.is_default_org) ?? orgs[0];
    if (o) { conn.zoho_org_id = String(o.organization_id); conn.zoho_org_name = String(o.name ?? o.organization_name ?? ""); }
  } catch (_) { /* keep going; status shows the missing organisation */ }
  await db("POST", "zoho_connection?on_conflict=org_id", { ...conn, connected_by: st[0].member_id, connected_at: new Date().toISOString() }, "resolution=merge-duplicates,return=minimal");
  return page("Zoho is connected", `ZIPPY can now send reports to <b>${(conn.zoho_org_name ?? "your Zoho organisation").replace(/[<>&]/g, "")}</b>. Close this tab and go back to ZIPPY.`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);
  try {
    if (req.method === "GET" && url.pathname.endsWith("/callback")) return await callback(url);
    if (req.method !== "POST") return json({ error: "Not found" }, 404);
    if (!ZID || !ZSECRET) throw new Fail("The Zoho app keys aren't set in HOH cloud yet (ZOHO_CLIENT_ID and ZOHO_CLIENT_SECRET).", 500);
    const b = await req.json().catch(() => ({}));
    const m = await caller(req);
    switch (b.action) {
      case "status": {
        const rows = await db("GET", `zoho_connection?select=zoho_org_name,zoho_org_id,connected_at,connected_by,api_domain&org_id=${eq(m.org_id)}`);
        if (!rows?.length) return json({ connected: false, can_connect: m.role === "admin" });
        const by = rows[0].connected_by ? await db("GET", `members?select=name&id=${eq(rows[0].connected_by)}`) : [];
        return json({ connected: true, can_connect: m.role === "admin", org_name: rows[0].zoho_org_name, org_id: rows[0].zoho_org_id,
          connected_at: rows[0].connected_at, connected_by: by?.[0]?.name ?? "", app_domain: rows[0].api_domain.replace("www.zohoapis", "expense.zoho") });
      }
      case "connect": {
        needAdmin(m);
        const state = [...crypto.getRandomValues(new Uint8Array(24))].map((x) => x.toString(16).padStart(2, "0")).join("");
        await db("POST", "zoho_oauth_state", { state, org_id: m.org_id, member_id: m.id }, "return=minimal");
        const q = new URLSearchParams({ scope: SCOPE, client_id: ZID, response_type: "code", access_type: "offline", prompt: "consent", redirect_uri: REDIRECT, state });
        return json({ url: `https://accounts.zoho.com/oauth/v2/auth?${q}` });
      }
      case "disconnect": {
        needAdmin(m);
        const rows = await db("GET", `zoho_connection?select=refresh_token,accounts_server&org_id=${eq(m.org_id)}`);
        if (rows?.length) await fetch(`${rows[0].accounts_server}/oauth/v2/token/revoke?token=${encodeURIComponent(rows[0].refresh_token)}`, { method: "POST" }).catch(() => {});
        await db("DELETE", `zoho_connection?org_id=${eq(m.org_id)}`, undefined, "return=minimal");
        return json({ ok: true });
      }
      case "lookup": {
        const L = await lookups(await getConn(m.org_id));
        return json({ categories: L.cats.map((x) => x.name), currencies: L.currencies.map((x) => x.code),
          customers: L.customers.map((x) => x.name), projects: L.projects.map((x) => x.name), warnings: L.warnings });
      }
      case "send": return json(await send(m, b));
      case "attach": return json(await attach(m, b));
      default: throw new Fail("Unknown action.");
    }
  } catch (e) {
    if (e instanceof Fail) return json({ error: e.message }, e.status);
    if (e instanceof ZohoError) return json({ error: `Zoho: ${e.message}` }, 502);
    console.error(e);
    return json({ error: `Something went wrong: ${(e as Error).message}` }, 500);
  }
});
