// Zip Receipt for Windows.
// Shows ../index.html (embedded at build time) in a WebView2 (Edge) window and adds what a browser can't:
// saving straight to Documents\Zip_Receipt and writing PDFs without a print dialog.
// Implements the same bridge commands as the Mac app (see mac/README.md): info, read, write, pdf, print, reveal, http.
using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace ZipReceipt;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

sealed class MainForm : Form
{
    const string Host = "zipreceipt.example";   // .example is reserved, so Windows never looks it up online
    static readonly string Docs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Zip_Receipt");
    static readonly string AppData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ZipReceipt");
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };
    static readonly HttpClient DownloadHttp = new() { Timeout = TimeSpan.FromMinutes(15) };

    // Gives the page window.zipNative(msg) -> Promise, the same contract index.html uses on the Mac.
    const string BridgeJs = @"(() => {
  if (window.zipNative || !window.chrome || !window.chrome.webview) return;
  let n = 0; const pending = new Map();
  window.chrome.webview.addEventListener('message', e => {
    const d = e.data; const p = pending.get(d.id); if (!p) return; pending.delete(d.id);
    if (d.error != null) p.reject(new Error(d.error)); else p.resolve(d.result);
  });
  window.zipNative = msg => new Promise((resolve, reject) => {
    const id = ++n; pending.set(id, { resolve, reject });
    window.chrome.webview.postMessage(Object.assign({}, msg, { __id: id }));
  });
})();";

    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    bool readyToClose;

    public MainForm()
    {
        Text = "Zip Receipt";
        ClientSize = new Size(1280, 860);
        MinimumSize = new Size(900, 600);
        StartPosition = FormStartPosition.CenterScreen;
        using (var ico = Assembly.GetExecutingAssembly().GetManifestResourceStream("ZipReceipt.AppIcon.ico"))
            if (ico != null) Icon = new Icon(ico);
        Controls.Add(web);
        Load += async (_, _) => await StartAsync();
        FormClosing += OnFormClosing;
    }

    async Task StartAsync()
    {
        try
        {
            // Unpack the app page next to the browser data (the install folder may be read-only).
            var appDir = Path.Combine(AppData, "app");
            Directory.CreateDirectory(appDir);
            using (var src = Assembly.GetExecutingAssembly().GetManifestResourceStream("ZipReceipt.index.html")!)
            using (var dst = File.Create(Path.Combine(appDir, "index.html")))
                src.CopyTo(dst);

            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(AppData, "WebView2"));
            await web.EnsureCoreWebView2Async(env);
            var core = web.CoreWebView2;
            core.SetVirtualHostNameToFolderMapping(Host, appDir, CoreWebView2HostResourceAccessKind.Allow);
            await core.AddScriptToExecuteOnDocumentCreatedAsync(BridgeJs);
            core.WebMessageReceived += OnMessage;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsZoomControlEnabled = true;

            // Keep the window on the app: a dropped file or a link must not replace it.
            core.NavigationStarting += (_, e) =>
            {
                if (e.Uri.StartsWith($"https://{Host}/", StringComparison.OrdinalIgnoreCase)) return;
                e.Cancel = true;
                OpenExternal(e.Uri);
            };
            core.NewWindowRequested += (_, e) => { e.Handled = true; OpenExternal(e.Uri); };

            core.Navigate($"https://{Host}/index.html");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this,
                "Zip Receipt couldn't start.\n\n" + ex.Message +
                "\n\nIf this mentions WebView2, install the free \"Microsoft Edge WebView2 Runtime\" from microsoft.com and try again.",
                "Zip Receipt", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    static void OpenExternal(string uri)
    {
        if (uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
            uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            uri.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase))
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
    }

    /// "2026-07/Receipts 2026-07.pdf" -> a path inside Documents\Zip_Receipt. Rejects anything that escapes it.
    static string SafePath(string? rel)
    {
        if (string.IsNullOrWhiteSpace(rel) || rel.StartsWith('/') || rel.Contains('\\') || rel.Contains(':'))
            throw new InvalidOperationException("bad path");
        var parts = rel.Split('/');
        if (parts.Any(p => p.Length == 0 || p == "." || p == "..")) throw new InvalidOperationException("bad path");
        return Path.Combine(new[] { Docs }.Concat(parts).ToArray());
    }

    static string? Str(JsonElement r, string name) =>
        r.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static bool Bool(JsonElement r, string name) =>
        r.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        int id = 0; object? result = null; string? error = null;
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var r = doc.RootElement;
            id = r.GetProperty("__id").GetInt32();
            switch (Str(r, "cmd"))
            {
                case "info":
                    result = new { folder = Docs, platform = "windows" };
                    break;
                case "read":
                {
                    var path = SafePath(Str(r, "path"));
                    result = File.Exists(path) ? await File.ReadAllTextAsync(path) : null;
                    break;
                }
                case "write":
                {
                    var path = SafePath(Str(r, "path"));
                    var text = Str(r, "text") ?? throw new InvalidOperationException("nothing to write");
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    var tmp = path + ".tmp";
                    if (Bool(r, "base64")) await File.WriteAllBytesAsync(tmp, Convert.FromBase64String(text));   // binary files such as the Excel report
                    else await File.WriteAllTextAsync(tmp, text);
                    File.Move(tmp, path, overwrite: true);
                    result = path;
                    break;
                }
                case "pdf":
                {
                    var path = SafePath(Str(r, "path"));
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    bool landscape = Bool(r, "landscape");
                    var ps = web.CoreWebView2.Environment.CreatePrintSettings();
                    ps.Orientation = landscape ? CoreWebView2PrintOrientation.Landscape : CoreWebView2PrintOrientation.Portrait;
                    ps.PageWidth = 8.27; ps.PageHeight = 11.69;            // A4, inches
                    double m = landscape ? 0.315 : 0.47;                     // 8 mm / 12 mm, matches the page CSS
                    ps.MarginTop = m; ps.MarginBottom = m; ps.MarginLeft = m; ps.MarginRight = m;
                    ps.ShouldPrintBackgrounds = true;
                    ps.ShouldPrintHeaderAndFooter = false;
                    ps.ScaleFactor = 1.0;
                    if (!await web.CoreWebView2.PrintToPdfAsync(path, ps))
                        throw new InvalidOperationException("Windows couldn't write the PDF. Is it open in another program?");
                    result = path;
                    break;
                }
                case "print":
                    web.CoreWebView2.ShowPrintUI(CoreWebView2PrintDialogKind.Browser);
                    result = true;
                    break;
                case "reveal":
                {
                    Directory.CreateDirectory(Docs);
                    string? target = null;
                    try { target = Str(r, "path") is string p ? SafePath(p) : null; } catch { }
                    if (target != null && File.Exists(target))
                        Process.Start("explorer.exe", $"/select,\"{target}\"");
                    else
                        Process.Start("explorer.exe", $"\"{Docs}\"");
                    result = true;
                    break;
                }
                case "http":
                {
                    // Fallback for reaching the HOH cloud / Google Sheet if the page's own request is blocked
                    var url = Str(r, "url") ?? "";
                    if (!url.StartsWith("https://") && !url.StartsWith("http://")) throw new InvalidOperationException("bad url");
                    var body = Str(r, "body");
                    var method = Str(r, "method") ?? (body == null ? "GET" : "POST");
                    using var msg = new HttpRequestMessage(new HttpMethod(method), url);
                    string? contentType = null;
                    if (r.TryGetProperty("headers", out var hs) && hs.ValueKind == JsonValueKind.Object)
                        foreach (var h in hs.EnumerateObject())
                        {
                            var v = h.Value.ToString();
                            if (h.Name.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)) contentType = v;
                            else msg.Headers.TryAddWithoutValidation(h.Name, v);
                        }
                    if (body != null)
                    {
                        msg.Content = new StringContent(body, System.Text.Encoding.UTF8);
                        msg.Content.Headers.ContentType = System.Net.Http.Headers.MediaTypeHeaderValue.Parse(contentType ?? "text/plain");
                    }
                    using var resp = await Http.SendAsync(msg);
                    var text = await resp.Content.ReadAsStringAsync();
                    result = Bool(r, "full") ? new { status = (int)resp.StatusCode, text } : text;
                    break;
                }
                case "update":
                {
                    // Download the new installer from GitHub, run it quietly, and close; it reopens Zip Receipt when done
                    var url = Str(r, "url") ?? "";
                    if (!url.StartsWith("https://")) throw new InvalidOperationException("bad update link");
                    var exe = Path.Combine(Path.GetTempPath(), "Zip-Receipt-Setup.exe");
                    using (var resp = await DownloadHttp.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
                    {
                        resp.EnsureSuccessStatusCode();
                        await using var fs = File.Create(exe);
                        await resp.Content.CopyToAsync(fs);
                    }
                    Process.Start(new ProcessStartInfo(exe, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS") { UseShellExecute = true });
                    result = true;
                    _ = Task.Run(async () => { await Task.Delay(800); BeginInvoke(new Action(Close)); });
                    break;
                }
                default:
                    error = "unknown command";
                    break;
            }
        }
        catch (Exception ex) { error = ex.Message; }
        web.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { id, result, error }));
    }

    // Give the page a moment to write any unsaved change before closing.
    async void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (readyToClose || web.CoreWebView2 == null) return;
        e.Cancel = true;
        try { await web.CoreWebView2.ExecuteScriptAsync("window.flushSave && window.flushSave()"); await Task.Delay(400); }
        catch { }
        readyToClose = true;
        Close();
    }
}
