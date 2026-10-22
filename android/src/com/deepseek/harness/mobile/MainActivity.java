package com.deepseek.harness.mobile;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Color;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.Window;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;

/**
 * Minimal WebView shell around the DeepSeek Harness web GUI.
 *
 *  - target URL comes from the generated AppConfig (config/settings.json -> build)
 *  - on 401 with a stored cookie: reload once (the auth cookie is SameSite=Strict, so a
 *    navigation triggered from outside the browser does not carry it on the first hop)
 *  - on 401 without a cookie: ask the user to paste the tokenized launch URL
 *  - on load failure (VPN down, host unreachable): show a retry page instead of a blank screen
 */
public class MainActivity extends Activity {

    private WebView web;
    private boolean dialogShowing = false;
    private int reloadAttempts = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Window w = getWindow();
        w.setStatusBarColor(Color.parseColor("#101114"));
        w.setNavigationBarColor(Color.parseColor("#101114"));

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#101114"));

        web = new WebView(this);
        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " DSHMobile/1.2");

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);

        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                CookieManager.getInstance().flush();
                view.evaluateJavascript(
                        "(function(){var t=document.body?document.body.innerText:'';" +
                        "return t.indexOf('authentication required')>=0?'AUTH':'OK';})()",
                        new android.webkit.ValueCallback<String>() {
                            @Override
                            public void onReceiveValue(String value) {
                                if (value != null && value.indexOf("AUTH") >= 0) {
                                    handleAuthRequired();
                                } else {
                                    dialogShowing = false;
                                    reloadAttempts = 0;
                                }
                            }
                        });
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    showOfflinePage(error == null ? "" : String.valueOf(error.getDescription()));
                }
            }
        });

        String start = null;
        if (getIntent() != null) start = getIntent().getDataString();
        loadTarget(start != null && start.startsWith("http") ? start : AppConfig.HOME);
    }

    private void loadTarget(String url) {
        try {
            web.loadUrl(url);
        } catch (Throwable t) {
            showOfflinePage(String.valueOf(t.getMessage()));
        }
    }

    /** Shown when the main frame cannot load at all (VPN disconnected, host down, ...). */
    private void showOfflinePage(String reason) {
        String safeReason = reason == null ? "" : reason.replace("<", "").replace(">", "");
        String html =
                "<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>" +
                "<style>html,body{margin:0;height:100%;background:#101114;color:#e8e8ea;" +
                "font-family:-apple-system,'Noto Sans CJK SC',sans-serif}" +
                "body{display:flex;flex-direction:column;align-items:center;justify-content:center;" +
                "gap:16px;padding:28px;box-sizing:border-box;text-align:center}" +
                "h2{font-size:18px;margin:0;font-weight:600}" +
                "p{margin:0;color:#8f8f98;font-size:13px;line-height:1.7}" +
                "button{margin-top:10px;background:#4d6bfe;color:#fff;border:0;border-radius:999px;" +
                "padding:14px 36px;font-size:15px}" +
                ".r{font-size:11px;opacity:.45;max-width:80%;word-break:break-all}</style>" +
                "<h2>Cannot reach the desktop</h2>" +
                "<p>Make sure this phone is connected to your VPN / Tailscale,<br>then tap retry.</p>" +
                "<div class='r'>" + safeReason + "</div>" +
                "<button onclick=\"location.href='./'\">Retry</button>";
        web.loadDataWithBaseURL(AppConfig.HOME, html, "text/html", "utf-8", null);
    }

    private void handleAuthRequired() {
        final String cookie = CookieManager.getInstance().getCookie(AppConfig.HOME);
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (cookie != null && cookie.length() > 0) {
                    if (reloadAttempts < 2) {
                        reloadAttempts++;
                        web.evaluateJavascript("location.reload()", null);
                        return;
                    }
                }
                if (!dialogShowing) {
                    dialogShowing = true;
                    promptToken();
                }
            }
        });
    }

    private String clipboardText() {
        try {
            ClipboardManager cb = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cb == null || !cb.hasPrimaryClip()) return null;
            ClipData clip = cb.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) return null;
            CharSequence text = clip.getItemAt(0).coerceToText(this);
            return text == null ? null : text.toString().trim();
        } catch (Throwable t) {
            return null;
        }
    }

    private void promptToken() {
        final EditText input = new EditText(this);
        input.setSingleLine(false);
        input.setHint("https://.../?token=...");
        String clip = clipboardText();
        if (clip != null && clip.indexOf("token=") >= 0) input.setText(clip);

        new AlertDialog.Builder(this)
                .setTitle("Sign in")
                .setMessage("Copy the tokenized URL printed by dsh web on your desktop " +
                        "(scripts/status.cmd shows it), put it on the clipboard, then paste it here.")
                .setView(input)
                .setPositiveButton("Sign in", new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface d, int which) {
                        String u = input.getText().toString().trim();
                        if (u.length() > 0) {
                            dialogShowing = false;
                            loadTarget(u);
                        }
                    }
                })
                .setNegativeButton("Cancel", new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface d, int which) {
                        dialogShowing = false;
                    }
                })
                .show();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
