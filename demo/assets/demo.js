/* Trilivy Demo add-on - the prospect side (2026-10-15).
 *
 *  - locked features ([data-demo-feature]) open a pitch popup instead of navigating
 *  - one action everywhere: "Talk to a person" (a ticket in the platform's Talk to a Person)
 *  - "Ask about this" opens the Sales Engineer assistant, when one is configured
 *  - moments: one event-triggered tip at a time, never while typing or reading
 *  - beacon: time on page, via navigator.sendBeacon
 *  - menu codes (2026-10-19): menugen menus follow C.map.nodes item by item (SPT/SPS/SPO/OPE/HID)
 *  - story coach (2026-10-19): the running story's task panel on its live page (C.story)
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
  // the session ended (a reply that is not JSON, or 401/403): stop the timed calls
  var sessionGone = false;
  function get(op, q) {
    if (sessionGone) return Promise.resolve({ ok: false });
    return fetch(API + "&op=" + op + (q || ""), { credentials: "same-origin", redirect: "manual" })
      .then(function (r) {
        if (r.type === "opaqueredirect" || r.status === 401 || r.status === 403 || r.status === 302) { sessionGone = true; return { ok: false }; }
        return r.json();
      }).catch(function () { return { ok: false }; });
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

  // opts.fb = the card to use when this one is not written yet; opts.open = {href, target, path}:
  // the item may run (menu code SPO), so the card ends in "Open it now"; opts.cont: the page
  // is already open behind the card ("Continue to the page").
  function openCard(feature, via, opts) {
    opts = opts || {};
    return get("card", "&feature=" + encodeURIComponent(feature) + "&via=" + (via || "popup") + (opts.fb ? "&fb=" + encodeURIComponent(opts.fb) : "")).then(function (j) {
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
      // the card's proof_html, shown as "See for yourself" (2026-10-20, was "Proof")
      if (c.proof || (it && it.proof)) tabs.push(["proof", "See for yourself", c.proof, it && it.proof]);
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
      ctas(ov.querySelector(".dp-cta"), feature, opts);
    });
  }

  // "Open it now" (SPO) or "Continue to the page" (the page is open behind it), and Close.
  // No Contact us on the cards (2026-10-20, the user): it lives only in the DEMO bar.
  function ctas(bar, feature, opts) {
    opts = opts || {};
    if (opts.closed) {
      var nt = document.createElement("span");
      nt.className = "dp-note";
      nt.textContent = "Opens in your own pilot: in this shared demo it would show more than your sandbox.";
      bar.appendChild(nt);
    }
    if (opts.open || opts.cont) {
      var go = document.createElement("button");
      go.className = "dp-btn p";
      go.textContent = opts.open ? "Open it now →" : "Continue to the page";
      go.onclick = function () {
        ev("card_open_now", feature, { href: opts.open ? opts.open.href : location.pathname });
        close();
        if (opts.open) openNow(opts.open);
      };
      bar.appendChild(go);
    }
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
  var LINK_CSS = "a.demo-lk::after{content:' \\1F512';font-size:.85em;opacity:.7}"
    + "a.demo-spo::after{content:' \\2726';font-size:.8em;opacity:.8}"
    + "a.demo-ci::after{content:' \\24D8';font-size:.85em;opacity:.7}"
    + ".demo-gi{display:inline-grid;place-items:center;width:17px;height:17px;margin-left:6px;border-radius:50%;"
    + "background:rgba(255,179,0,.9);color:#1b2333;font:700 11px/1 Arial,sans-serif;cursor:pointer;vertical-align:1px}";

  // ---------------------------------------------------------------- menu codes
  // The menus drawn by menugen (Manage, KB, Quick: /ain5py/<area>/menu.cfm) follow
  // the menu codes item by item (C.map.nodes[area][trail] = [mode, card, own, group, code]),
  // so the same page can be locked in one place and open in another.
  var NODES = MAP.nodes || {};
  function menuArea(doc) {
    try {
      var m = /^\/ain5py\/([a-z_]+)\/menu\.cfm$/i.exec(doc.location.pathname);
      return m && NODES[m[1].toLowerCase()] && doc.querySelector("ul.menu-root") ? m[1].toLowerCase() : "";
    } catch (e) { return ""; }
  }
  function clean(s) { return String(s || "").replace(/\s+/g, " ").trim(); }
  // a label as the menu config has it (the ⓘ added to a group header is not part of it)
  function labelOf(lb) {
    if (!lb) return "";
    if (!lb.dataset.demoLbl) lb.dataset.demoLbl = clean(lb.textContent);
    return lb.dataset.demoLbl;
  }
  function trailOf(el) {
    var li = el.closest("li.menu-item"), parts = [];
    var own = el.querySelector(".menu-label");
    parts.push(own ? labelOf(own) : clean(el.textContent));
    var p = li && li.parentElement ? li.parentElement.closest("li.menu-item") : null;
    while (p) {
      var lb = p.querySelector(":scope > .menu-link.parent .menu-label");
      if (lb) parts.unshift(labelOf(lb));
      p = p.parentElement ? p.parentElement.closest("li.menu-item") : null;
    }
    return parts.join(" › ");
  }
  function markMenu(doc, area) {
    var tree = NODES[area];
    doc.querySelectorAll("ul.menu-root .menu-link").forEach(function (el) {
      if (el.dataset.demoNd === "1") return;
      el.dataset.demoNd = "1";
      // the map's keys arrive lower case (demo.toJson)
      var n = tree[trailOf(el).toLowerCase()];
      if (!n) return;
      var li = el.closest("li.menu-item");
      if (n[0] === "hidden") { if (li) li.style.display = "none"; return; }
      el.dataset.demoCode = n[4]; el.dataset.demoMode = n[0]; el.dataset.demoCard = n[1];
      if (el.classList.contains("parent")) {
        // a group with its own card (SPT / SPS / SPO): an ⓘ on the header, and the card on the first opening per session
        if (n[2] && n[0] !== "open") {
          var lab = el.querySelector(".menu-label");
          labelOf(lab);
          var gi = doc.createElement("span");
          gi.className = "demo-gi"; gi.textContent = "i"; gi.title = "What this is";
          gi.dataset.demoGi = "1";
          (lab || el).appendChild(gi);
        }
        return;
      }
      el.dataset.demoMk = "1";
      // ✦ = its card, then the real page; ⓘ = its card only (the page is not safe to open in a shared demo yet)
      if (n[0] === "pitch") el.classList.add("demo-ci");
      else if (n[0] === "guard") el.classList.add("demo-spo");
    });
  }
  function openNow(o) {
    try { sessionStorage.setItem("trlvGuardSkip", o.path || ""); } catch (e) {}
    var t = o.target || "";
    if (t === "_blank") { window.open(o.href, "_blank"); return; }
    var fr = t ? (document.getElementsByName(t)[0] || document.getElementById(t)) : null;
    if (fr && fr.tagName === "IFRAME") fr.src = o.href; else location.href = o.href;
  }
  function menuClick(e) {
    var gi = e.target.closest ? e.target.closest("[data-demo-gi]") : null;
    var el = e.target.closest ? e.target.closest(".menu-link[data-demo-code]") : null;
    if (!el) return;
    var code = el.dataset.demoCode, mode = el.dataset.demoMode, card = el.dataset.demoCard;
    if (el.classList.contains("parent")) {
      if (gi) { e.preventDefault(); e.stopPropagation(); openCard(card, "group"); return; }
      if (mode === "open" || !el.querySelector("[data-demo-gi]")) return;
      // first opening of the group in this session: its card (the group still opens)
      var k = "trlvGrp_" + trailOf(el), seen = false;
      try { seen = sessionStorage.getItem(k) === "1"; sessionStorage.setItem(k, "1"); } catch (x) { seen = true; }
      if (!seen) { ev("group_card", card, { trail: trailOf(el) }); setTimeout(function () { openCard(card, "group"); }, 250); }
      return;
    }
    if (mode === "pitch") { e.preventDefault(); e.stopPropagation(); openCard(card, "menu", { closed: true }); return; }
    if (mode === "guard") {
      e.preventDefault(); e.stopPropagation();
      var path = null;
      try { path = keyOf(new URL(el.getAttribute("href"), el.ownerDocument.baseURI)); } catch (x) {}
      openCard(card, "menu", { open: { href: el.href, target: el.getAttribute("target") || "", path: path } });
    }
  }

  function markLinks(doc) {
    if (!doc || !doc.body) return;
    if (!doc.getElementById("demoLkCss")) {
      var st = doc.createElement("style"); st.id = "demoLkCss"; st.textContent = LINK_CSS;
      (doc.head || doc.body).appendChild(st);
    }
    var area = menuArea(doc);
    if (area) {
      markMenu(doc, area);
      if (!doc.__demoMenuClick) { doc.__demoMenuClick = true; doc.addEventListener("click", menuClick, true); }
    }
    doc.querySelectorAll("a[href]").forEach(function (a) {
      if (a.dataset.demoMk === "1" || a.closest("#demoBar,#demoOv,.demo-bar,#demoCoach")) return;
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
      // SPO: the item's own sales card over the open page
      if (j.card) { openCard(j.card, "guard", { fb: j.fb || "", cont: true }); return; }
      var ov = shell("In your demo", j.title, false);
      current = { feature: "guard" };
      ov.querySelector(".dp-tabs").style.display = "none";
      ov.querySelector(".dp-body").innerHTML = j.html; // written by operators (Access map)
      var bar = ov.querySelector(".dp-cta");
      var ok = document.createElement("button");
      ok.className = "dp-btn p"; ok.textContent = "Got it"; ok.onclick = close;
      bar.appendChild(ok);
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
    // opened with "Open it now" from its card: the card was just read
    var skip = null;
    try { skip = sessionStorage.getItem("trlvGuardSkip"); if (skip === path) sessionStorage.removeItem("trlvGuardSkip"); } catch (e) {}
    if (skip === path) return;
    // the running story step's pages (its page and its extra pages): the coach panel explains them, no card
    if (C.story && C.story.key) {
      var bare = path.split("?")[0];
      if (bare === C.story.target_path || (C.story.extras || []).some(function (x) { return String(x.url).split("?")[0].toLowerCase() === bare; })) return;
    }
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
  // Signing out ends the session before this page closes: a beacon sent then was
  // remembered by the platform as "the page to return to" and the next sign-in
  // landed on {"ok": false} (2026-10-20). No beacon after a sign-out click.
  var signingOut = false;
  document.addEventListener("click", function (e) {
    var a = e.target.closest ? e.target.closest("a[href]") : null;
    if (a && /logout|signout|sign_out/i.test(a.getAttribute("href") || "")) signingOut = true;
  }, true);
  function flush() {
    if (signingOut) return;
    var ms = visibleMs + (visibleSince ? Date.now() - visibleSince : 0);
    if (ms < 3000) return;
    beacon([{ type: "page_time", page: location.pathname + location.search, ms: ms }]);
    visibleMs = 0; if (visibleSince) visibleSince = Date.now();
  }
  window.addEventListener("pagehide", flush);

  // ---------------------------------------------------------------- story coach
  // A running story (Quick Start, 2026-10-19; it replaces the old 4-step tour):
  // on the step's real page a docked panel shows the task with Back / Next; on
  // any other page it offers the way back. Slides are drawn by p=story itself.
  function coach() {
    var S = C.story;
    if (!S || !S.key || C.where === "frame" || document.querySelector("[data-demo-story]")) return;
    var here = location.pathname.toLowerCase();
    // the step's page, or one of its extra pages (opened from the coach panel's links)
    var onStep = S.kind === "live" && ((S.target_path && here === S.target_path)
      || (S.extras || []).some(function (x) { return String(x.url).split("?")[0].toLowerCase() === here; }));
    var MIN = "trlvCoachMin";
    var box = document.createElement("aside");
    box.id = "demoCoach"; box.className = "demo-coach";
    box.setAttribute("aria-label", S.title);
    var head = '<div class="dc-top"><span class="dc-k">' + esc(S.title) + ' · step ' + S.n + ' of ' + S.total + '</span>'
      + '<button class="dc-min" aria-label="Minimise">–</button></div>';
    var dots = '<div class="dc-dots">' + S.dots.map(function (t, i) {
      return '<i class="' + (i + 1 === S.n ? "on" : (i + 1 < S.n ? "done" : "")) + '" title="' + esc(t) + '"></i>';
    }).join("") + '</div>';
    var body;
    if (onStep) {
      body = (S.kicker ? '<div class="dc-kick">' + esc(S.kicker) + '</div>' : "")
        + '<div class="dc-h">' + esc(S.heading) + '</div>'
        + (S.task ? '<div class="dc-task">' + S.task + '</div>' : "")   // written by operators (Stories)
        // the step's extra pages (Stories: "Extra pages the prospect can open during this step")
        + (S.extras && S.extras.length ? '<div class="dc-extra">Also on this step: ' + S.extras.map(function (x) {
            return '<a href="' + esc(x.url) + '">' + esc(x.label) + '</a>';
          }).join(" · ") + '</div>' : "")
        + '<div class="dc-ok" hidden>✓ Done. Well done — go on when you are ready.</div>';
    } else {
      body = '<div class="dc-h">' + esc(S.heading) + '</div><p class="dc-p">Your tour is waiting on this step.</p>';
    }
    var nav = '<div class="dc-nav">'
      + (S.prev ? '<a class="dc-b" href="' + esc(S.prev) + '">← Back</a>' : "")
      + (onStep && S.card ? '<a class="dc-b" href="#" data-demo-feature="' + esc(S.card) + '">Why it matters</a>' : "")
      + (onStep ? '<a class="dc-b p" href="' + esc(S.next) + '">' + (S.n < S.total ? "Next →" : "Finish ✓") + '</a>'
                : '<a class="dc-b p" href="' + esc(S.target) + '">Take me there →</a>')
      + '</div><a class="dc-exit" href="' + esc(S.exit) + '">Leave the tour</a>';
    box.innerHTML = head + dots + '<div class="dc-body">' + body + '</div>' + nav;
    var pill = document.createElement("button");
    pill.className = "demo-coach-pill"; pill.hidden = true;
    pill.textContent = "▶ " + S.title + " · " + S.n + "/" + S.total;
    document.body.appendChild(box); document.body.appendChild(pill);
    function setMin(m) {
      box.hidden = m; pill.hidden = !m;
      try { sessionStorage.setItem(MIN, m ? "1" : "0"); } catch (e) {}
    }
    box.querySelector(".dc-min").onclick = function () { setMin(true); };
    pill.onclick = function () { setMin(false); };
    try { if (sessionStorage.getItem(MIN) === "1") setMin(true); } catch (e) {}
    // the task is done (done_when): Next lights up
    if (onStep && S.watch) {
      var t = setInterval(function () {
        if (document.hidden) return;
        get("story_check").then(function (j) {
          if (!j.ok || !j.done) return;
          clearInterval(t);
          var ok = box.querySelector(".dc-ok"); if (ok) ok.hidden = false;
          var nx = box.querySelector(".dc-b.p"); if (nx) nx.classList.add("pulse");
          if (box.hidden) setMin(false);
        });
      }, 6000);
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", coach); else coach();
})();
