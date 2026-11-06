/**
 * Zip Receipt – Google Sheet backend
 * Phones send expenses here; Zip Receipt on the computer reads them back.
 *
 * Setup (once): see README.md in this folder.
 *   1. In your Google Sheet: Extensions → Apps Script, paste this file, save.
 *   2. Run the "setup" function once and allow access. Copy the access code from the log.
 *   3. Deploy → New deployment → Web app → Execute as: Me, Who has access: Anyone.
 */

const HEADERS = ['ID', 'Logged at', 'Date', 'Who', 'Amount', 'Currency', 'Description',
                 'Business', 'Category', 'Project', 'Shop receipt', 'Photo', 'Note', 'Status'];
const SHEET_NAME = 'Expenses';
const FOLDER_NAME = 'Zip Receipt Photos';

/* ---------- run once from the editor ---------- */
function setup() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const props = PropertiesService.getScriptProperties();
  props.setProperty('SPREADSHEET_ID', ss.getId());

  let sh = ss.getSheetByName(SHEET_NAME);
  if (!sh) sh = ss.insertSheet(SHEET_NAME);
  sh.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]).setFontWeight('bold').setBackground('#e9edf2');
  sh.setFrozenRows(1);
  sh.getRange('A:D').setNumberFormat('@');           // keep IDs, dates and names as plain text
  sh.getRange('E:E').setNumberFormat('#,##0.##');
  sh.setColumnWidth(1, 90); sh.setColumnWidth(7, 260); sh.setColumnWidth(12, 220);

  let folderId = props.getProperty('FOLDER_ID');
  if (!folderId) {
    folderId = DriveApp.createFolder(FOLDER_NAME).getId();
    props.setProperty('FOLDER_ID', folderId);
  }
  if (!props.getProperty('ACCESS_CODE')) {
    const code = Utilities.getUuid().replace(/-/g, '').slice(0, 10).toUpperCase();
    props.setProperty('ACCESS_CODE', code);
  }
  Logger.log('Setup done. Your access code is: ' + props.getProperty('ACCESS_CODE'));
  Logger.log('Photos go to the Drive folder "' + FOLDER_NAME + '".');
}

/** Run this if you ever need to see the access code again. */
function showAccessCode() {
  Logger.log('Access code: ' + PropertiesService.getScriptProperties().getProperty('ACCESS_CODE'));
}

/** Run this to replace the access code (e.g. a phone was lost). Every phone then needs the new setup link. */
function newAccessCode() {
  const code = Utilities.getUuid().replace(/-/g, '').slice(0, 10).toUpperCase();
  PropertiesService.getScriptProperties().setProperty('ACCESS_CODE', code);
  Logger.log('New access code: ' + code);
}

/* ---------- web app ---------- */
function doGet(e) {
  const p = (e && e.parameter) || {};
  if (!p.action) return ContentService.createTextOutput('Zip Receipt sheet is running.');
  if (!codeOk(p.code)) return json({ ok: false, error: 'Wrong access code.' });
  if (p.action === 'ping') return json({ ok: true, rows: Math.max(0, sheet().getLastRow() - 1) });
  if (p.action === 'list') return json({ ok: true, rows: listRows() });
  return json({ ok: false, error: 'Unknown action.' });
}

function doPost(e) {
  let body;
  try { body = JSON.parse(e.postData.contents); } catch (err) { return json({ ok: false, error: 'Bad request.' }); }
  const p = (e && e.parameter) || {};
  if (!codeOk(body.code || p.code)) return json({ ok: false, error: 'Wrong access code.' });
  if ((body.action || p.action) === 'add') return json(addEntry(body.entry || {}, body.photo));
  return json({ ok: false, error: 'Unknown action.' });
}

/* ---------- helpers ---------- */
function codeOk(code) {
  const real = PropertiesService.getScriptProperties().getProperty('ACCESS_CODE');
  return !!real && String(code || '').trim().toUpperCase() === real;
}

function sheet() {
  const id = PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  const ss = id ? SpreadsheetApp.openById(id) : SpreadsheetApp.getActiveSpreadsheet();
  return ss.getSheetByName(SHEET_NAME);
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function clean(v, max) { return String(v == null ? '' : v).replace(/^[=+\-@]/, "'$&").slice(0, max || 500); }

function addEntry(x, photoBase64) {
  if (!x.id || !(Number(x.amount) > 0)) return { ok: false, error: 'Missing amount.' };
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = sheet();
    // Already received? (the phone retries if the connection dropped) -> report success, don't duplicate
    const found = sh.getRange('A:A').createTextFinder(String(x.id)).matchEntireCell(true).findNext();
    if (found) return { ok: true, id: x.id, duplicate: true, photoUrl: sh.getRange(found.getRow(), 12).getValue() };

    let photoUrl = '';
    if (photoBase64) {
      const folder = DriveApp.getFolderById(PropertiesService.getScriptProperties().getProperty('FOLDER_ID'));
      const month = /^\d{4}-\d{2}/.test(x.date || '') ? x.date.slice(0, 7) : 'Undated';
      const sub = folder.getFoldersByName(month).hasNext() ? folder.getFoldersByName(month).next() : folder.createFolder(month);
      const name = [x.date, x.who, x.amount + ' ' + (x.currency || ''), x.description].filter(String).join(' – ').slice(0, 120) + '.jpg';
      const blob = Utilities.newBlob(Utilities.base64Decode(photoBase64), 'image/jpeg', name);
      photoUrl = sub.createFile(blob).getUrl();
    }
    sh.appendRow([
      clean(x.id, 60), new Date().toISOString(), clean(x.date, 10), clean(x.who, 80), Number(x.amount),
      x.currency === 'USD' ? 'USD' : 'IQD', clean(x.description), clean(x.business, 120), clean(x.category, 80),
      clean(x.project, 80), x.noShopReceipt ? 'No' : 'Yes', photoUrl, clean(x.note), ''
    ]);
    return { ok: true, id: x.id, photoUrl: photoUrl };
  } finally {
    lock.releaseLock();
  }
}

function listRows() {
  const sh = sheet();
  const n = sh.getLastRow() - 1;
  if (n < 1) return [];
  const tz = Session.getScriptTimeZone();
  const vals = sh.getRange(2, 1, n, HEADERS.length).getValues();
  const fmt = v => v instanceof Date ? Utilities.formatDate(v, tz, 'yyyy-MM-dd') : String(v || '');
  return vals.filter(r => r[0]).map(r => ({
    id: String(r[0]), loggedAt: r[1] instanceof Date ? r[1].toISOString() : String(r[1] || ''), date: fmt(r[2]),
    who: String(r[3] || ''), amount: Number(r[4]) || 0, currency: String(r[5] || 'IQD'), description: String(r[6] || ''),
    business: String(r[7] || ''), category: String(r[8] || ''), project: String(r[9] || ''), hasReceipt: String(r[10] || ''),
    photoUrl: String(r[11] || ''), note: String(r[12] || ''), status: String(r[13] || '')
  }));
}
