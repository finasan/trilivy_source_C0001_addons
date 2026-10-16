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
      var tabs = [["why", "Why it matters", c.why]];
      if (c.how) tabs.push(["how", "How it works", c.how]);
      if (c.objections && c.objections.length) tabs.push(["obj", "You might be wondering…", null]);
      if (c.proof) tabs.push(["proof", "Proof", c.proof]);
      var tabBar = ov.querySelector(".dp-tabs"), body = ov.querySelector(".dp-body");
      tabBar.style.display = tabs.length > 1 ? "" : "none";
      function show(key) {
        tabBar.querySelectorAll("button").forEach(function (b) { b.classList.toggle("on", b.dataset.k === key); });
        var t = tabs.filter(function (x) { return x[0] === key; })[0];
        if (key === "obj") {
          body.innerHTML = c.objections.map(function (o, i) {
            return '<details class="dp-obj" data-i="' + i + '"><summary>' + esc(o.q) + '</summary><p>' + esc(o.a) + '</p></details>';
          }).join("");
          body.querySelectorAll("details").forEach(function (d) {
            d.addEventListener("toggle", function () {
              if (d.open) ev("objection_open", feature, { q: c.objections[+d.dataset.i].q });
            });
          });
        } else {
          body.innerHTML = t[2] || ""; // card HTML is written and verified by operators (cx_demo_pitch)
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
