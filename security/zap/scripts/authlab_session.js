// AuthLab session propagation for ZAP
// Type: HTTP Sender
// Engine: ECMAScript : Graal.js

var API_BASE = "http://authlab:5000/api/v1";
var BOOTSTRAP_URL = API_BASE + "/auth/session";

var sessionCookie = null; // "session=...."
var csrfToken = null;

function isApiRequest(uri) {
    return uri.indexOf(API_BASE) === 0;
}

function isBootstrapRequest(uri, method) {
    return uri === BOOTSTRAP_URL && method === "POST";
}

function needsCsrf(method) {
    return method === "POST" || method === "PUT" || method === "PATCH" || method === "DELETE";
}

function extractCookiePair(setCookieValue) {
    if (!setCookieValue) {
        return null;
    }
    return String(setCookieValue).split(";", 1)[0];
}

function extractCsrfToken(rawBody) {
    var parsed = JSON.parse(String(rawBody));

    // support either:
    // { "user": "...", "csrf_token": "..." }
    // or
    // { "data": { "user": "...", "csrf_token": "..." } }
    if (parsed && parsed.csrf_token) {
        return String(parsed.csrf_token);
    }

    if (parsed && parsed.data && parsed.data.csrf_token) {
        return String(parsed.data.csrf_token);
    }

    return null;
}

function sendingRequest(msg, initiator, helper) {
    var uri = String(msg.getRequestHeader().getURI().toString());
    var method = String(msg.getRequestHeader().getMethod()).toUpperCase();

    if (!isApiRequest(uri)) {
        return;
    }

    if (sessionCookie) {
        msg.getRequestHeader().setHeader("Cookie", sessionCookie);
    }

    if (csrfToken && needsCsrf(method)) {
        msg.getRequestHeader().setHeader("X-CSRF-Token", csrfToken);
    }
}

function responseReceived(msg, initiator, helper) {
    var uri = String(msg.getRequestHeader().getURI().toString());
    var method = String(msg.getRequestHeader().getMethod()).toUpperCase();

    if (!isBootstrapRequest(uri, method)) {
        return;
    }

    var status = msg.getResponseHeader().getStatusCode();
    if (status !== 200) {
        print("[authlab-session] bootstrap status=" + status);
        return;
    }

    var setCookie = msg.getResponseHeader().getHeader("Set-Cookie");
    if (setCookie) {
        sessionCookie = extractCookiePair(setCookie);
        print("[authlab-session] stored session cookie");
    } else {
        print("[authlab-session] no Set-Cookie header on bootstrap response");
    }

    try {
        var token = extractCsrfToken(msg.getResponseBody().toString());
        if (token) {
            csrfToken = token;
            print("[authlab-session] stored csrf token");
        } else {
            print("[authlab-session] csrf token not found in bootstrap JSON");
        }
    } catch (e) {
        print("[authlab-session] failed to parse bootstrap JSON: " + e);
    }
}