package com.calevans.frame;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
    private static final String URL = "https://example.com/dashboard";
    // Wi-Fi comes up after the home screen starts, and frame-fixmac.sh bounces it during boot.
    private static final long RETRY_MS = 10000;

    private WebView web;
    private boolean failed;
    private final Handler handler = new Handler();
    private final Runnable retry = new Runnable() {
        @Override
        public void run() {
            load();
        }
    };
    private final BroadcastReceiver netChange = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (failed && isOnline()) {
                load();
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return false;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    failed = true;
                    // Replace Chrome's error page with a blank screen while we wait for the network.
                    view.loadData("<html><body style='background:#000'></body></html>", "text/html", null);
                    handler.removeCallbacks(retry);
                    handler.postDelayed(retry, RETRY_MS);
                }
            }
        });
        setContentView(web);
        registerReceiver(netChange, new IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION));
        load();
    }

    private void load() {
        handler.removeCallbacks(retry);
        failed = false;
        web.loadUrl(URL);
    }

    private boolean isOnline() {
        NetworkInfo info = ((ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE)).getActiveNetworkInfo();
        return info != null && info.isConnected();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            hideSystemUi();
        }
    }

    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }

    @Override
    public void onBackPressed() {
        // A kiosk home screen has nowhere to go back to; only step back within the page history.
        if (web.canGoBack()) {
            web.goBack();
        }
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(retry);
        unregisterReceiver(netChange);
        web.destroy();
        super.onDestroy();
    }
}
