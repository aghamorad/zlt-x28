package com.morad.zltx28;

import android.app.Activity;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public class MainActivity extends Activity {
    private WebView webView;
    private String sessionId = "";
    private String routerHost = "192.168.70.1";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setBackgroundColor(0xFF0D0F14);
        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient());
        webView.addJavascriptInterface(this, "ZltNative");

        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView != null && webView.canGoBack()) {
            webView.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private static String readStream(InputStream in) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        int n;
        while ((n = in.read(buf)) != -1) bos.write(buf, 0, n);
        return new String(bos.toByteArray(), StandardCharsets.UTF_8);
    }

    private static String sha256Hex(String input) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] digest = md.digest(input.getBytes(StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        for (byte b : digest) sb.append(String.format("%02x", b));
        return sb.toString();
    }

    private JSONObject postCgi(JSONObject body) throws Exception {
        URL cgi = new URL("http://" + routerHost + "/cgi-bin/http.cgi");
        HttpURLConnection conn = (HttpURLConnection) cgi.openConnection();
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setConnectTimeout(4500);
        conn.setReadTimeout(6000);
        conn.setRequestProperty("Content-Type", "application/json");
        byte[] raw = body.toString().getBytes(StandardCharsets.UTF_8);
        try (OutputStream os = conn.getOutputStream()) {
            os.write(raw);
        }
        return new JSONObject(readStream(conn.getInputStream()));
    }

    private String login(String password) throws Exception {
        String pw = (password == null || password.isEmpty()) ? "admin" : password;
        JSONObject cReq = new JSONObject();
        cReq.put("cmd", 232);
        cReq.put("method", "GET");
        cReq.put("sessionId", "");
        JSONObject cRes = postCgi(cReq);
        String token = cRes.optString("token", "");
        if (token.isEmpty()) {
            throw new Exception("Router did not return a login challenge.");
        }
        String hash = sha256Hex(token + pw);
        JSONObject lReq = new JSONObject();
        lReq.put("cmd", 100);
        lReq.put("method", "POST");
        lReq.put("sessionId", "zlt" + System.currentTimeMillis());
        lReq.put("username", "admin");
        lReq.put("passwd", hash);
        lReq.put("isAutoUpgrade", "0");
        lReq.put("subcmd", 0);
        JSONObject lRes = postCgi(lReq);
        String sid = lRes.optString("sessionId", "");
        if (sid.isEmpty()) {
            throw new Exception("Router rejected the admin password.");
        }
        this.sessionId = sid;
        return sid;
    }

    @JavascriptInterface
    public String readRouterStatus(String password) {
        try {
            String sid = login(password);
            JSONObject req = new JSONObject();
            req.put("cmd", 0);
            req.put("method", "GET");
            req.put("sessionId", sid);
            JSONObject res = postCgi(req);

            JSONObject out = new JSONObject();
            out.put("ok", true);
            out.put("operator", res.optString("operatorName", res.optString("networkOperator", "Connected")));
            out.put("network_type", res.optString("networkType", res.optString("netMode", "4G/5G")));
            out.put("wan_ip", res.optString("wanIp", res.optString("ipAddr", "—")));
            out.put("rsrp", res.optString("rsrp", "—"));
            out.put("sinr", res.optString("sinr", "—"));
            out.put("firmware", res.optString("fwVersion", res.optString("softwareVersion", "1.5.x")));
            return out.toString();
        } catch (Exception e) {
            try {
                JSONObject err = new JSONObject();
                err.put("ok", false);
                err.put("error", e.getMessage());
                return err.toString();
            } catch (Exception ignored) {
                return "{\"ok\":false}";
            }
        }
    }

    @JavascriptInterface
    public String fixRouterOneClick(String password) {
        try {
            String sid = login(password);
            // 1. Auto-Dial ON (cmd 222)
            JSONObject dial = new JSONObject();
            dial.put("cmd", 222);
            dial.put("method", "POST");
            dial.put("sessionId", sid);
            dial.put("dialMode", "1");
            postCgi(dial);

            // 2. Clear stuck band lock (cmd 161)
            JSONObject band = new JSONObject();
            band.put("cmd", 161);
            band.put("method", "POST");
            band.put("sessionId", sid);
            band.put("band4gRadio", "0");
            band.put("band5gRadio", "0");
            postCgi(band);

            // 3. Fix empty Auto APN -> set default_flag onto MCI mcinet (cmd 248)
            JSONObject apnGet = new JSONObject();
            apnGet.put("cmd", 248);
            apnGet.put("method", "GET");
            apnGet.put("sessionId", sid);
            JSONObject apnRes = postCgi(apnGet);
            JSONArray apnList = apnRes.optJSONArray("apn_list");
            if (apnList != null && apnList.length() > 0) {
                int mciIdx = -1;
                for (int i = 0; i < apnList.length(); i++) {
                    JSONObject a = apnList.optJSONObject(i);
                    if (a != null && "mcinet".equalsIgnoreCase(a.optString("apnName"))) {
                        mciIdx = i;
                        break;
                    }
                }
                if (mciIdx >= 0) {
                    for (int i = 0; i < apnList.length(); i++) {
                        JSONObject a = apnList.optJSONObject(i);
                        if (a != null) a.put("default_flag", i == mciIdx ? "1" : "0");
                    }
                    JSONObject apnPost = new JSONObject();
                    apnPost.put("cmd", 248);
                    apnPost.put("method", "POST");
                    apnPost.put("sessionId", sid);
                    apnPost.put("apn_list", apnList);
                    postCgi(apnPost);
                }
            }
            return "Fixed! Auto-Dial is ON, stuck band locks are cleared, and the MCI (mcinet) APN is set as default.";
        } catch (Exception e) {
            return "Could not fix router: " + e.getMessage() + " (Make sure your phone is connected to the ZLT X28 Wi-Fi at 192.168.70.1).";
        }
    }

    @JavascriptInterface
    public String setBandMode(String password, String mode) {
        try {
            String sid = login(password);
            JSONObject band = new JSONObject();
            band.put("cmd", 161);
            band.put("method", "POST");
            band.put("sessionId", sid);
            if ("auto".equals(mode)) {
                band.put("band4gRadio", "0");
                band.put("band5gRadio", "0");
            } else if ("b3".equals(mode)) {
                band.put("band4gRadio", "1");
                band.put("band4gMask", "4");
                band.put("band5gRadio", "0");
            } else if ("b3b7".equals(mode)) {
                band.put("band4gRadio", "1");
                band.put("band4gMask", "68");
                band.put("band5gRadio", "0");
            }
            postCgi(band);
            return "Band configuration updated (" + mode.toUpperCase() + ").";
        } catch (Exception e) {
            return "Band update failed: " + e.getMessage();
        }
    }

    @JavascriptInterface
    public String rebootRouter(String password) {
        try {
            String sid = login(password);
            JSONObject req = new JSONObject();
            req.put("cmd", 6);
            req.put("method", "POST");
            req.put("sessionId", sid);
            postCgi(req);
            return "ZLT X28 is restarting (takes about 60 seconds).";
        } catch (Exception e) {
            return "Reboot failed: " + e.getMessage();
        }
    }
}
