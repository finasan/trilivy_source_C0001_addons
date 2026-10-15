<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)>
    <cfoutput><div style="max-width:640px;margin:40px auto;font-family:Arial,sans-serif">This page belongs to a prospect's demo.</div></cfoutput><cfexit>
</cfif>
<cfset samples = queryExecute("SELECT DISTINCT title FROM #demo.names(d.pid).base#_doc WHERE ingest_log_id IS NULL OR ingest_log_id NOT IN (
                                 SELECT id FROM ingest_log WHERE tablename IN (:a, :b)) ORDER BY title LIMIT 80",
    {a: demo.names(d.pid).base, b: "public." & demo.names(d.pid).base}, {datasource: "airrag2"})>
<cfoutput>
<style>
.md{font:15px/1.55 var(--fs);color:##1b2333;max-width:900px;margin:18px auto 60px;padding:0 16px}
.md h1{font-size:24px;margin:6px 0 6px}.md .muted{color:##5d6779}
.md .drop{border:2px dashed ##c9d2e3;border-radius:14px;padding:26px;text-align:center;background:##fafbfe;margin:14px 0}
.md .drop.over{border-color:##2457d6;background:##f3f6fe}
.md table{width:100%;border-collapse:collapse;font-size:14px}.md td,.md th{padding:8px;border-bottom:1px solid ##e3e7ef;text-align:left}
.md .st{font-size:12px;font-weight:700;padding:1px 9px;border-radius:999px;background:##f1f3f8}
.md .st.ready{background:##e3f5ee;color:##11845b}.md .st.failed{background:##fde9e7;color:##c0392b}.md .st.running,.md .st.queued{background:##fff3df;color:##b26a00}
.md .btn{padding:7px 14px;border-radius:8px;border:1px solid ##c9d2e3;background:##fff;cursor:pointer;font-weight:600}
.md .btn.primary{background:##2457d6;color:##fff;border-color:##2457d6}
.md .msg{padding:9px 13px;border-radius:8px;margin:8px 0;display:none}.md .msg.ok{background:##e3f5ee;display:block}.md .msg.err{background:##fde9e7;display:block}
</style>
<div class="md">
    <h1>My documents</h1>
    <p class="muted">Load a few of your own documents and ask the assistant about them. They go only into your private sandbox and are deleted when your demo ends.
       Please do not upload other people's personal data or secrets.</p>
    <div class="drop" id="drop">
        <p style="margin:0 0 10px"><b>Drop a file here</b> or</p>
        <input type="file" id="file" style="display:none">
        <button class="btn primary" onclick="document.getElementById('file').click()">Choose a file</button>
        <p class="muted" id="limits" style="margin:10px 0 0;font-size:13px"></p>
    </div>
    <div class="msg" id="msg"></div>
    <table><thead><tr><th>Document</th><th>Size</th><th>Uploaded</th><th>State</th><th></th></tr></thead><tbody id="rows"><tr><td colspan="5" class="muted">Loading…</td></tr></tbody></table>
    <p style="margin-top:14px"><a href="/ain5py/boty/boty_full.cfm?wsDsn=#urlEncodedFormat(d.db)#" target="_blank">Open the assistant and ask about them →</a></p>
    <details style="margin-top:18px"><summary class="muted">Sample documents already in your demo (#samples.recordCount#)</summary>
        <p class="small muted" style="font-size:13px">#encodeForHTML(valueList(samples.title, " · "))#</p></details>
</div>
<script>
(function(){
  var API = "/ain5py/addon_api.cfm?a=demo&p=docs_api";
  var rows = document.getElementById("rows"), msg = document.getElementById("msg"), timer = null;
  function esc(s){ return String(s == null ? "" : s).replace(/[&<>"]/g, function(c){ return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }
  function say(t, ok){ msg.textContent = t; msg.className = "msg " + (ok ? "ok" : "err"); }
  var label = {queued: "waiting", running: "loading…", ready: "ready", failed: "failed"};
  function load(){
    fetch(API + "&op=list", {credentials: "same-origin"}).then(function(r){ return r.json(); }).then(function(j){
      if (!j.ok) { rows.innerHTML = '<tr><td colspan="5">' + esc(j.error || "error") + '</td></tr>'; return; }
      var L = j.limits;
      document.getElementById("limits").textContent = j.types.replace(/,/g, ", ") + " · up to " + L.file_mb + " MB each · "
        + L.used_files + " of " + L.files_total + " documents · " + (L.ingests_day - L.used_today) + " loads left today";
      if (!j.docs.length) { rows.innerHTML = '<tr><td colspan="5" class="muted">No documents yet.</td></tr>'; }
      else rows.innerHTML = j.docs.map(function(d){
        return '<tr><td>' + esc(d.name) + '</td><td>' + d.kb + ' KB</td><td>' + esc(d.at) + '</td><td><span class="st ' + d.state + '">'
          + (label[d.state] || d.state) + '</span></td><td><button class="btn" data-del="' + d.id + '">Delete</button></td></tr>';
      }).join("");
      clearTimeout(timer);
      if (j.docs.some(function(d){ return d.state === "queued" || d.state === "running"; })) timer = setTimeout(load, 5000);
    });
  }
  function upload(f){
    if (!f) return;
    var fd = new FormData(); fd.append("file", f); fd.append("op", "upload");
    say("Uploading " + f.name + "…", true);
    fetch(API + "&op=upload", {method: "POST", body: fd, credentials: "same-origin"}).then(function(r){ return r.json(); })
      .then(function(j){ say(j.ok ? j.message : j.error, j.ok); load(); }).catch(function(){ say("The upload failed.", false); });
  }
  document.getElementById("file").addEventListener("change", function(e){ upload(e.target.files[0]); e.target.value = ""; });
  var drop = document.getElementById("drop");
  ["dragenter","dragover"].forEach(function(t){ drop.addEventListener(t, function(e){ e.preventDefault(); drop.classList.add("over"); }); });
  ["dragleave","drop"].forEach(function(t){ drop.addEventListener(t, function(e){ e.preventDefault(); drop.classList.remove("over"); }); });
  drop.addEventListener("drop", function(e){ upload(e.dataTransfer.files[0]); });
  rows.addEventListener("click", function(e){
    var id = e.target.getAttribute("data-del"); if (!id) return;
    if (!confirm("Delete this document from your demo?")) return;
    var fd = new FormData(); fd.append("op", "delete"); fd.append("id", id);
    fetch(API + "&op=delete", {method: "POST", body: fd, credentials: "same-origin"}).then(function(r){ return r.json(); })
      .then(function(j){ say(j.ok ? j.message : j.error, j.ok); load(); });
  });
  load();
})();
</script>
</cfoutput>
