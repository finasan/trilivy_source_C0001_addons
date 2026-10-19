/* Trilivy Demo add-on - the prospect side (2026-10-15).
 *
 *  - locked features ([data-demo-feature]) open a pitch popup instead of navigating
 *  - one action everywhere: "Talk to a person" (a ticket in the platform's Talk to a Person)
 *  - "Ask about this" opens the Sales Engineer assistant, when one is configured
 *  - moments: one event-triggered tip at a time, never while typing or reading
 *  - beacon: time on page and the welcome tour, via navigator.sendBeacon
 * Config: window.TRLV_DEMO (printed by the page_top hook).
 */
(function () {
  "use strict";
  var C = window.TRLV_DEMO;
  if (!C || window.__trlvDemo) return;
  window.__trlvDemo = true;

  var API = C.api, BEACON = C.beacon, openSince = 0, current = null;

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function post(op, data) {
    var fd = new FormData();
    fd.append("op", op);
    Object.keys(data || {}).forEach(function (k) { fd.append(k, data[k]); });
    return fetch(API + "&op=" + op, { method: "POST", body: fd, credentials: "same-origin" })
      .then(function (r) { return r.json(); }).catch(function () { return { ok: false }; });
  }
  function get(op, q) {
    return fetch(API + "&op=" + op + (q || ""), { credentials: "same-origin" })
      .then(function (r) { return r.json(); }).catch(function () { return { ok: false }; });
  }
  function beacon(events) {
    try {
      var body = JSON.stringify(events);
      if (navigator.sendBeacon) navigator.sendBeacon(BEACON, new Blob([body], { type: "application/json" }));
      else fetch(BEACON, { method: "POST", body: body, credentials: "same-origin", keepalive: true });
    } catch (e) { /* never break the page */ }
  }
  function ev(type, feature, extra) { return post("event", Object.assign({ type: type, feature: feature || "" }, extra || {})); }

  // ---------------------------------------------------------------- popup
  function close() {
    var ov = document.getElementById("demoOv");
    if (!ov) return;
    if (current) ev("popup_closed", current.feature, { ms: Date.now() - openSince, where: C.where });
    ov.remove(); current = null;
    document.removeEventListener("keydown", onKey);
  }
  function onKey(e) { if (e.key === "Escape") close(); }

  function shell(kicker, headline, draft) {
    close();
    var ov = document.createElement("div");
    ov.className = "demo-ov"; ov.id = "demoOv";
    ov.innerHTML = '<div class="demo-pop" role="dialog" aria-modal="true" aria-labelledby="dpH">'
      + '<div class="dp-top"><div class="dp-k">' + esc(kicker) + (draft ? '<span class="dp-draft">DRAFT</span>' : "") + '</div>'
      + '<div class="dp-h" id="dpH">' + esc(headline) + '</div><button class="dp-x" aria-label="Close">&times;</button></div>'
      + '<div class="dp-tabs"></div><div class="dp-body"></div><div class="dp-cta"></div></div>';
    ov.addEventListener("click", function (e) { if (e.target === ov) close(); });
    ov.querySelector(".dp-x").onclick = close;
    document.body.appendChild(ov);
    document.addEventListener("keydown", onKey);
    openSince = Date.now();
    setTimeout(function () { var x = ov.querySelector(".dp-x"); if (x) x.focus(); }, 30);
    return ov;
  }

  function openCard(feature, via) {
    return get("card", "&feature=" + encodeURIComponent(feature) + "&via=" + (via || "popup")).then(function (j) {
      if (!j.ok) return;
      var c = j.card;
      var ov = shell(c.kicker || "Part of the full platform", c.headline, c.draft);
      current = { feature: feature };
      // IT prospects: the business card plus the IT card's text under "For IT teams" in each tab (2026-10-16)
      var it = c.it && c.it.headline ? c.it : null;
      var objs = (c.objections || []).concat(it ? it.objections || [] : []);
      var nBiz = (c.objections || []).length;
      var tabs = [["why", "Why it matters", c.why, it && it.why]];
      if (c.how || (it && it.how)) tabs.push(["how", "How it works", c.how, it && it.how]);
      if (objs.length) tabs.push(["obj", "You might be wondering…", null, null]);
      if (c.proof || (it && it.proof)) tabs.push(["proof", "Proof", c.proof, it && it.proof]);
      var tabBar = ov.querySelector(".dp-tabs"), body = ov.querySelector(".dp-body");
      tabBar.style.display = tabs.length > 1 ? "" : "none";
      function itHead() {
        return '<div class="dp-it"><div class="dp-it-sub">For IT teams' + (it.draft ? '<span class="dp-draft">DRAFT</span>' : "")
          + '</div><div class="dp-it-h">' + esc(it.headline) + '</div>';
      }
      function objHtml(from, to) {
        return objs.slice(from, to).map(function (o, i) {
          return '<details class="dp-obj" data-i="' + (from + i) + '"><summary>' + esc(o.q) + '</summary><p>' + esc(o.a) + '</p></details>';
        }).join("");
      }
      function show(key) {
        tabBar.querySelectorAll("button").forEach(function (b) { b.classList.toggle("on", b.dataset.k === key); });
        var t = tabs.filter(function (x) { return x[0] === key; })[0];
        if (key === "obj") {
          body.innerHTML = objHtml(0, nBiz) + (it && objs.length > nBiz ? itHead() + objHtml(nBiz) + '</div>' : "");
          body.querySelectorAll("details").forEach(function (d) {
            d.addEventListener("toggle", function () {
              if (d.open) ev("objection_open", feature, { q: objs[+d.dataset.i].q });
            });
          });
        } else {
          // card HTML is written and verified by operators (cx_demo_pitch)
          body.innerHTML = (t[2] || "") + (t[3] ? itHead() + t[3] + '</div>' : "");
        }
        if (c.canask) {
          var a = document.createElement("div");
          a.className = "dp-ask";
          a.innerHTML = '<input type="text" maxlength="300" placeholder="Ask anything about this feature…"><button class="dp-btn">Ask</button>';
          body.appendChild(a);
          var go = function () { askAbout(feature, a.querySelector("input").value); };
          a.querySelector("button").onclick = go;
          a.querySelector("input").addEventListener("keydown", function (e) { if (e.key === "Enter") go(); });
        }
      }
      tabs.forEach(function (t, i) {
        var b = document.createElement("button");
        b.textContent = t[1]; b.dataset.k = t[0];
        b.onclick = function () { show(t[0]); if (i) ev("pitch_tab", feature, { tab: t[0] }); };
        tabBar.appendChild(b);
      });
      show("why");
      ctas(ov.querySelector(".dp-cta"), feature);
    });
  }

  // One action only: Talk to a person (2026-10-15: no booking, no wish list).
  function ctas(bar, feature) {
    var b = document.createElement("button");
    b.className = "dp-btn p";
    b.textContent = "Contact us";
    b.onclick = function () { ev("cta_click", feature, { cta: "talk" }); talk(feature, ""); };
    bar.appendChild(b);
    var back = document.createElement("button");
    back.className = "dp-btn"; back.style.marginLeft = "auto"; back.textContent = "Close";
    back.onclick = close; bar.appendChild(back);
  }

  function note(text) {
    var body = document.querySelector("#demoOv .dp-body");
    if (!body) return;
    var d = document.createElement("div");
    d.className = "dp-ok"; d.textContent = text;
    body.insertBefore(d, body.firstChild);
  }

  function talk(feature, prefill) {
    var ov = shell("Trilivy", "Contact us", false);
    current = { feature: feature || "talk" };
    ov.querySelector(".dp-tabs").style.display = "none";
    var body = ov.querySelector(".dp-body");
    body.innerHTML = "<p>Write your question or what you would like to know. It is sent to the Trilivy team.</p>"
      + '<textarea maxlength="1000" placeholder="Your message">' + esc(prefill || "") + "</textarea>";
    var bar = ov.querySelector(".dp-cta");
    var send = document.createElement("button");
    send.className = "dp-btn p"; send.textContent = "Send";
    send.onclick = function () {
      send.disabled = true;
      post("talk", { feature: feature || "", message: body.querySelector("textarea").value }).then(function (j) {
        body.innerHTML = '<div class="dp-ok">' + esc(j.message || "Your message has been sent.") + "</div>";
        send.remove();
      });
    };
    bar.appendChild(send);
    var c = document.createElement("button");
    c.className = "dp-btn"; c.textContent = "Close"; c.onclick = close; bar.appendChild(c);
  }

  function askAbout(feature, question) {
    post("ask", { feature: feature, question: question || "" }).then(function (j) {
      if (!j.ok) { talk(feature, question); return; }
      var body = document.querySelector("#demoOv .dp-body");
      if (!body) return;
      body.innerHTML = (question ? '<p class="muted">Ask: <b>' + esc(question) + "</b> (type it in the assistant below)</p>" : "")
        + '<iframe src="' + esc(j.url) + '" title="Ask about this feature"></iframe>';
      try { if (question && navigator.clipboard) navigator.clipboard.writeText(question); } catch (e) {}
    });
  }

  // ---------------------------------------------------------------- access map
  // C.map = {pages: {path: mode}, rx: [[regex, mode], ...]} for this experience
  // (Demo Console > Access map). Links to Hidden pages are removed, links to
  // Locked pages get a lock, and an "Open with guardrail" page shows its
  // instructions once per session + a "What can I do here?" button. Same-origin
  // frames (the Manage / JumpStart menus) are treated the same way.
  var MAP = C.map || { pages: {}, rx: [] };
  var RX = (MAP.rx || []).map(function (r) {
    try { return [new RegExp(r[0]), r[1]]; } catch (e) { return null; }
  }).filter(Boolean);
  // A sectioned page (the Instance Control Panel's own sections) is keyed
  // path?section=x[&lms_tab=y]; the most specific Access map row wins.
  function modeOf(path) {
    path = String(path || "").toLowerCase();
    var k = path;
    while (true) {
      if (MAP.pages && Object.prototype.hasOwnProperty.call(MAP.pages, k)) return MAP.pages[k];
      if (k.indexOf("?") < 0) break;
      k = k.indexOf("&") >= 0 ? k.replace(/&[^&]*$/, "") : k.split("?")[0];
    }
    path = path.split("?")[0];
    for (var i = 0; i < RX.length; i++) if (RX[i][0].test(path)) return RX[i][1];
    return "pitch";
  }
  function keyOf(u) {
    var p = u.pathname.toLowerCase(), sp = (MAP.sect || {})[p];
    if (!sp) return p;
    var parts = [];
    for (var i = 0; i < sp.params.length; i++) {
      var v = (u.searchParams.get(sp.params[i]) || "").replace(/[^A-Za-z0-9_-]/g, "").toLowerCase();
      if (!v || (i === 0 && v === sp.dflt)) break;
      parts.push(sp.params[i] + "=" + v);
    }
    return parts.length ? p + "?" + parts.join("&") : p;
  }
  function pathOf(href, doc) {
    try {
      var u = new URL(href, doc.baseURI);
      if (u.origin !== location.origin) return null;
      return keyOf(u);
    } catch (e) { return null; }
  }
  var LINK_CSS = "a.demo-lk::after{content:' \\1F512';font-size:.85em;opacity:.7}";
  function markLinks(doc) {
    if (!doc || !doc.body) return;
    if (!doc.getElementById("demoLkCss")) {
      var st = doc.createElement("style"); st.id = "demoLkCss"; st.textContent = LINK_CSS;
      (doc.head || doc.body).appendChild(st);
    }
    doc.querySelectorAll("a[href]").forEach(function (a) {
      if (a.dataset.demoMk === "1" || a.closest("#demoBar,#demoOv,.demo-bar")) return;
      a.dataset.demoMk = "1";
      var p = pathOf(a.getAttribute("href"), doc);
      if (!p || p === "/ain5py/addon.cfm" || p === "/ain5py/addon_api.cfm" || p.indexOf("/ain5py/login/") === 0) return;
      // the front door (logo links) goes to the demo home, and image links get no lock
      if (/^\/ain5py\/(index\.cfm|menu\.cfm)?$/.test(p) || a.querySelector("img,svg")) return;
      var m = modeOf(p);
      if (m === "hidden") {
        var li = a.closest("li");
        (li && li.querySelectorAll("a").length === 1 ? li : a).style.display = "none";
      } else if (m === "pitch") {
        a.classList.add("demo-lk");
      }
    });
  }

  var guardPath = null;
  function openGuard(path, via) {
    return get("guard", "&path=" + encodeURIComponent(path) + "&via=" + (via || "auto")).then(function (j) {
      if (!j.ok) return;
      var ov = shell("In your demo", j.title, false);
      current = { feature: "guard" };
      ov.querySelector(".dp-tabs").style.display = "none";
      ov.querySelector(".dp-body").innerHTML = j.html; // written by operators (Access map)
      var bar = ov.querySelector(".dp-cta");
      var ok = document.createElement("button");
      ok.className = "dp-btn p"; ok.textContent = "Got it"; ok.onclick = close;
      bar.appendChild(ok);
      var t = document.createElement("button");
      t.className = "dp-btn"; t.style.marginLeft = "auto"; t.textContent = "Contact us";
      t.onclick = function () { talk("", "About " + (j.label || "") + ": "); };
      bar.appendChild(t);
    });
  }
  // The instructions show each time the prospect ARRIVES at a guardrail page
  // (from another page), not on a reload or a save on the same page (2026-10-16:
  // once per session looked like "the guardrail does not work").
  // slot = where the page is shown (the top window, or one named frame): each keeps
  // its own "last page", so the chat window's frame does not count as a visit.
  function pageLoaded(path, slot) {
    if (!path) return;
    var help = document.getElementById("demoHelp");
    var last = null, k = "trlvGuardLast_" + (slot || "top");
    try { last = sessionStorage.getItem(k); sessionStorage.setItem(k, path); } catch (e) { last = null; }
    if (modeOf(path) !== "guard") {
      if (help && guardPath && guardPath === path) help.hidden = true;
      return;
    }
    guardPath = path;
    if (help) help.hidden = false;
    if (last !== path && !document.getElementById("demoOv")) openGuard(path, "auto");
  }
  function watchDoc(doc) {
    if (!doc || !doc.body || doc.__demoWatched) return;
    doc.__demoWatched = true;
    markLinks(doc);
    var t = 0;
    try {
      new MutationObserver(function () {
        clearTimeout(t);
        t = setTimeout(function () { markLinks(doc); hookFrames(doc); }, 150);
      }).observe(doc.body, { childList: true, subtree: true });
    } catch (e) {}
    hookFrames(doc);
  }
  function hookFrames(doc) {
    doc.querySelectorAll("iframe,frame").forEach(function (f) {
      if (f.__demoHooked || f.closest("#demoOv")) return;
      f.__demoHooked = true;
      var onload = function () {
        try {
          var fd = f.contentDocument;
          if (!fd) return;
          var loc = f.contentWindow.location;
          if (loc.protocol.indexOf("http") !== 0) return;   // about:blank (a frame not loaded yet)
          watchDoc(fd);
          pageLoaded(keyOf(new URL(loc.href)), f.id || f.name || "frame");
        } catch (e) { /* another origin: leave it */ }
      };
      f.addEventListener("load", onload);
      try { if (f.contentDocument && f.contentDocument.readyState === "complete") onload(); } catch (e) {}
    });
  }
  function startMap() {
    watchDoc(document);
    // inside a frame, demo.js of the framed page uses that frame's slot
    var slot = "top";
    try { if (window.self !== window.top && window.frameElement) slot = window.frameElement.id || window.frameElement.name || "frame"; } catch (e) {}
    pageLoaded(keyOf(new URL(location.href)), slot);
    var help = document.getElementById("demoHelp");
    if (help) help.addEventListener("click", function (e) { e.preventDefault(); if (guardPath) openGuard(guardPath, "help"); });
  }
  // inside a frame the top window's script does this
  if (C.where !== "frame") {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", startMap); else startMap();
  }

  // ---------------------------------------------------------------- clicks
  document.addEventListener("click", function (e) {
    var el = e.target.closest ? e.target.closest("[data-demo-feature],[data-demo-action]") : null;
    if (!el || el.closest("#demoOv")) return;
    var action = el.getAttribute("data-demo-action"), feature = el.getAttribute("data-demo-feature");
    if (action === "talk") { e.preventDefault(); talk(feature || ""); return; }
    if (feature && !action) { e.preventDefault(); openCard(feature, "click"); }
  }, true);

  // ---------------------------------------------------------------- moments
  function busy() {
    if (document.getElementById("demoOv") || document.hidden) return true;
    var a = document.activeElement;
    if (a && (a.tagName === "TEXTAREA" || (a.tagName === "INPUT" && a.type === "text")) && a.value) return true;
    // the chat page marks a streaming answer on <body>; also skip while any element says it is busy
    return !!document.querySelector("[aria-busy='true'], .is-streaming, .typing-indicator:not([hidden])");
  }
  function moments() {
    if (busy()) return;
    get("moment").then(function (j) { if (j.ok && j.moment && !busy()) openCard(j.moment, "moment"); });
  }
  setTimeout(moments, 20000);
  setInterval(moments, 60000);

  // ---------------------------------------------------------------- beacon
  var visibleSince = document.hidden ? 0 : Date.now(), visibleMs = 0;
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) { if (visibleSince) visibleMs += Date.now() - visibleSince; visibleSince = 0; flush(); }
    else visibleSince = Date.now();
  });
  function flush() {
    var ms = visibleMs + (visibleSince ? Date.now() - visibleSince : 0);
    if (ms < 3000) return;
    beacon([{ type: "page_time", page: location.pathname + location.search, ms: ms }]);
    visibleMs = 0; if (visibleSince) visibleSince = Date.now();
  }
  window.addEventListener("pagehide", flush);

  // ---------------------------------------------------------------- tour
  function tour() {
    var KEY = "trlvDemoTour_" + C.pid, done = false;
    try { done = localStorage.getItem(KEY) === "1"; } catch (e) { done = true; }
    if (done || location.search.indexOf("p=welcome") < 0) return;
    var steps = [
      ["Welcome to your demo", "<p>This is your private copy of Trilivy. Everything you upload or ask stays in your own sandbox.</p>"],
      ["Start with the assistant", "<p>Open <b>Assistant</b> and ask about the sample company's HR and IT policies. Each answer lists the sources it used.</p>"],
      ["Try your own documents", "<p>Under <b>My documents</b> you can load a few files and ask about them a minute later.</p>"],
      ["Explore the locked parts", "<p>Items with a 🔒 are part of the full platform. Click any of them to see what it does, ask questions, or contact us.</p>"]
    ];
    var i = 0;
    function step() {
      var ov = shell("Quick tour · " + (i + 1) + " of " + steps.length, steps[i][0], false);
      current = null;
      ov.querySelector(".dp-tabs").style.display = "none";
      ov.querySelector(".dp-body").innerHTML = steps[i][1];
      var bar = ov.querySelector(".dp-cta");
      var next = document.createElement("button");
      next.className = "dp-btn p"; next.textContent = i < steps.length - 1 ? "Next" : "Start";
      next.onclick = function () {
        beacon([{ type: "tour_step", step: String(i + 1), page: location.pathname }]);
        i++;
        if (i < steps.length) step(); else { finish("tour_done"); close(); }
      };
      var skip = document.createElement("button");
      skip.className = "dp-btn"; skip.textContent = "Skip";
      skip.onclick = function () { finish("tour_skip"); close(); };
      bar.appendChild(next); bar.appendChild(skip);
    }
    function finish(t) {
      try { localStorage.setItem(KEY, "1"); } catch (e) {}
      beacon([{ type: t, step: String(i + 1), page: location.pathname }]);
    }
    step();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", tour); else tour();
})();
