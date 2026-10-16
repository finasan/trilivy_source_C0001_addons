<cfset activeTab = "access">
<cfinclude template="_ui.cfm">
<!--- Access map - page by page, what a prospect gets in each experience:
      Open, Open + guardrail (instructions popup, optional read-only), Locked
      (sales popup: the page's own card, else its group's) or Hidden (out of the
      menus). Empty = inherit from the feature map. Pages come from the platform
      menus (Scan the menus) and from pages prospects open. The safety label comes
      from the two-marker audit: a page that shows other prospects' data or
      changes the server is never opened, whatever is chosen here. --->
<cfset msg = ""><cfset msgKind = "ok"><cfset problems = []>
<cfset canEdit = listFind("admin,se", op.role) GT 0>
<cfset MODES = "open,guard,pitch,hidden">
<cfset LBL = {open: "Open", guard: "Open + guardrail", pitch: "Locked (popup)", hidden: "Hidden", capped: "Open (limits)"}>
<cfset AREAS = [["jumpstart", "JumpStart"], ["main_ai", "Main AI"], ["rag", "RAG dashboard"], ["manage", "Manage"], ["kb", "Knowledge menu"], ["quick", "Quick menu"], ["other", "Other pages prospects opened"]]>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif NOT canEdit><cfthrow message="Only operators with role admin or se can change the Access map."></cfif>
        <cfif (form.action ?: "") EQ "scan">
            <cfset r = demo.scanMenus()>
            <cfset parts = []>
            <cfloop collection="#r#" item="k"><cfset arrayAppend(parts, k & ": " & r[k])></cfloop>
            <cfset msg = "Menus scanned (links found per menu): " & arrayToList(parts, " · ")>
        <cfelseif (form.action ?: "") EQ "save">
            <cfset changed = 0>
            <cfset cur = queryExecute("SELECT * FROM cx_demo_pages", {}, {datasource: "addon_demo"})>
            <cfset byId = {}>
            <cfloop query="cur"><cfset byId[cur.id] = queryGetRow(cur, cur.currentRow)></cfloop>
            <cfloop list="#form.ids ?: ''#" item="id">
                <cfif NOT structKeyExists(byId, id)><cfcontinue></cfif>
                <cfset r = byId[id]>
                <cfset g = form["g_#id#"] ?: ""><cfset e = form["e_#id#"] ?: "">
                <cfif len(g) AND NOT listFind(MODES, g)><cfset g = ""></cfif>
                <cfif len(e) AND NOT listFind(MODES, e)><cfset e = ""></cfif>
                <cfset sf = form["sf_#id#"] ?: r.safety>
                <cfif NOT listFind("sandbox,boxwide,server,unknown", sf)><cfset sf = r.safety></cfif>
                <cfset ro = (form["ro_#id#"] ?: "") EQ "1" ? 1 : 0>
                <cfset gt = left(trim(form["gt_#id#"] ?: ""), 160)>
                <cfset gh = trim(form["gh_#id#"] ?: "")>
                <cfset ck = left(reReplace(lCase(form["ck_#id#"] ?: ""), "[^a-z0-9_]", "", "all"), 60)>
                <!--- never open a page that shows other prospects' data or changes the server --->
                <cfif listFind("boxwide,server", sf)>
                    <cfif listFind("open,guard", g)><cfset arrayAppend(problems, r.label & " (Guided)")><cfset g = r.guided_mode ?: ""><cfif listFind("open,guard", g)><cfset g = "pitch"></cfif></cfif>
                    <cfif listFind("open,guard", e)><cfset arrayAppend(problems, r.label & " (Full platform)")><cfset e = r.explorer_mode ?: ""><cfif listFind("open,guard", e)><cfset e = "pitch"></cfif></cfif>
                </cfif>
                <cfif g NEQ (r.guided_mode ?: "") OR e NEQ (r.explorer_mode ?: "") OR sf NEQ r.safety OR ro NEQ val(r.readonly)
                      OR gt NEQ (r.guard_title ?: "") OR gh NEQ (r.guard_html ?: "") OR ck NEQ (r.card_key ?: "")>
                    <cfset queryExecute("UPDATE cx_demo_pages SET guided_mode = :g, explorer_mode = :e, safety = :sf, readonly = :ro,
                                         guard_title = :gt, guard_html = :gh, card_key = :ck, updated_by = :by WHERE id = :id", {
                        g: {value: g, null: NOT len(g)}, e: {value: e, null: NOT len(e)}, sf: sf, ro: {value: ro, cfsqltype: "cf_sql_integer"},
                        gt: {value: gt, null: NOT len(gt)}, gh: {value: gh, null: NOT len(gh)}, ck: {value: ck, null: NOT len(ck)},
                        by: op.email ?: op.oid, id: {value: id, cfsqltype: "cf_sql_integer"}
                    }, {datasource: "addon_demo"})>
                    <cfset changed++>
                </cfif>
            </cfloop>
            <cfset demo.pagesChanged()>
            <cfset msg = changed & " page(s) saved. Prospects get the change within a minute.">
            <cfif arrayLen(problems)>
                <cfset msgKind = "warn">
                <cfset msg &= " Not opened, because they show other prospects' data or change the server: " & arrayToList(problems, ", ") & ".">
            </cfif>
        </cfif>
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
</cfif>

<cfparam name="url.area" default="">
<cfparam name="url.q" default="">
<cfparam name="url.show" default="">
<cfset rows = queryExecute("SELECT * FROM cx_demo_pages ORDER BY FIELD(area, 'jumpstart','main_ai','rag','manage','kb','quick','other'), sort, label", {}, {datasource: "addon_demo"})>
<cfset ownCards = {}>
<cfset qc = queryExecute("SELECT DISTINCT feature_key FROM cx_demo_pitch WHERE status <> 'retired'", {}, {datasource: "addon_demo"})>
<cfloop query="qc"><cfset ownCards[qc.feature_key] = 1></cfloop>
<cfset counts = {guided: {open: 0, capped: 0, guard: 0, pitch: 0, hidden: 0}, explorer: {open: 0, capped: 0, guard: 0, pitch: 0, hidden: 0}}>
<cfset list = []>
<cfloop query="rows">
    <cfset r = queryGetRow(rows, rows.currentRow)>
    <cfset r.fg = demo.classify(r.path, "guided")>
    <cfset r.fe = demo.classify(r.path, "explorer")>
    <cfset counts.guided[r.fg.mode] = (counts.guided[r.fg.mode] ?: 0) + 1>
    <cfset counts.explorer[r.fe.mode] = (counts.explorer[r.fe.mode] ?: 0) + 1>
    <cfif len(url.area) AND r.area NEQ url.area><cfcontinue></cfif>
    <cfif len(url.q) AND NOT findNoCase(url.q, r.label & " " & r.path & " " & (r.grp ?: ""))><cfcontinue></cfif>
    <cfif url.show EQ "unknown" AND r.safety NEQ "unknown"><cfcontinue></cfif>
    <cfif url.show EQ "set" AND NOT len((r.guided_mode ?: "") & (r.explorer_mode ?: ""))><cfcontinue></cfif>
    <cfif url.show EQ "fullopen" AND NOT listFind("open,capped,guard", r.fe.mode)><cfcontinue></cfif>
    <cfset arrayAppend(list, r)>
</cfloop>

<cfscript>
    function modeSelect(string name, string val, string inherited, boolean locked) {
        var h = '<select name="' & name & '" class="msel" data-cur="' & val & '"' & (canEdit ? "" : " disabled") & '>';
        h &= '<option value="">Inherit (' & LBL[inherited] & ')</option>';
        for (var m in listToArray(MODES)) {
            var off = locked && listFind("open,guard", m);
            h &= '<option value="' & m & '"' & (val == m ? " selected" : "") & (off ? " disabled" : "") & '>' & LBL[m] & (off ? " (unsafe)" : "") & '</option>';
        }
        return h & '</select>';
    }
    function effBadge(struct f) {
        var c = {open: "b-green", capped: "b-green", guard: "b-blue", pitch: "b-amber", hidden: "b-grey"};
        return '<span class="dbadge ' & (c[f.mode] ?: "b-grey") & '">' & LBL[f.mode] & '</span>';
    }
    function safeBadge(string s) {
        var c = {sandbox: ["b-green", "own sandbox only"], boxwide: ["b-red", "shows other prospects' data"], server: ["b-red", "changes the server"], unknown: ["b-grey", "not audited"]};
        return '<span class="dbadge ' & c[s][1] & '" title="' & c[s][2] & '">' & s & '</span>';
    }
</cfscript>

<cfoutput>
<style>
.dc .am td{padding:5px 6px}.dc .am select{width:auto;max-width:190px;padding:4px 6px;font-size:12.5px}
.dc .am .grp td{background:##f6f7fb;font-weight:700}
.dc .am .changed{outline:2px solid ##ffb300}
.dc .am details summary{cursor:pointer;color:##2457d6;font-size:12.5px}
.dc .am details input,.dc .am details textarea{margin-top:4px;font-size:12.5px}
.dc .savebar{position:sticky;bottom:0;background:##fff;border-top:1px solid ##e3e7ef;padding:10px 0;display:flex;gap:10px;align-items:center;z-index:5}
</style>
<h1>Access map</h1>
<p class="muted" style="margin-top:-6px">Page by page, what a prospect gets in each experience. <b>Open</b>: the page works. <b>Open + guardrail</b>: it works, with your instructions in a popup the first time (and a "What can I do here?" button); tick read-only to turn saving off on that page.
<b>Locked</b>: the sales popup, with the page's own card or else its group's. <b>Hidden</b>: removed from the menus. <b>Inherit</b> follows the feature map.</p>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>

<div class="grid">
    <cfloop list="guided,explorer" item="x">
    <div class="card"><div class="muted small">#x EQ "guided" ? "Guided" : "Full platform"# · #rows.recordCount# pages</div>
        <span class="dbadge b-green">#counts[x].open + counts[x].capped# open</span>
        <span class="dbadge b-blue">#counts[x].guard# guardrail</span>
        <span class="dbadge b-amber">#counts[x].pitch# locked</span>
        <span class="dbadge b-grey">#counts[x].hidden# hidden</span></div>
    </cfloop>
    <div class="card"><div class="muted small">Pages come from the platform menus</div>
        <form method="post" style="margin:4px 0 0"><input type="hidden" name="action" value="scan"><button class="btn" #canEdit ? "" : "disabled"#>Scan the menus now</button></form>
        <div class="small muted">Pages added by a new release start as Inherit (mostly Locked).</div></div>
</div>

<form method="get" style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:0 0 8px">
    <input type="hidden" name="a" value="demo"><input type="hidden" name="p" value="access">
    <select name="area" style="width:auto"><option value="">All menus</option>
        <cfloop array="#AREAS#" item="ar"><option value="#ar[1]#" #url.area EQ ar[1] ? "selected" : ""#>#ar[2]#</option></cfloop></select>
    <select name="show" style="width:auto">
        <option value="">All pages</option>
        <option value="set" #url.show EQ "set" ? "selected" : ""#>Chosen here (not inherited)</option>
        <option value="fullopen" #url.show EQ "fullopen" ? "selected" : ""#>Open in Full platform</option>
        <option value="unknown" #url.show EQ "unknown" ? "selected" : ""#>Not audited</option></select>
    <input type="text" name="q" value="#encodeForHTMLAttribute(url.q)#" placeholder="search label or path" style="width:220px">
    <button class="btn">Filter</button>
    <span class="muted small">#arrayLen(list)# shown</span>
</form>

<form method="post" id="amForm">
<input type="hidden" name="action" value="save">
<table class="am">
<tr><th>Page</th><th>Safety</th><th>Guided</th><th>Full platform</th><th>Guardrail</th><th>Card</th></tr>
<cfset lastKey = "">
<cfset ids = []>
<cfloop array="#list#" item="r">
    <cfset key = r.area & "|" & (r.grp ?: "")>
    <cfif key NEQ lastKey>
        <cfset arName = r.area>
        <cfloop array="#AREAS#" item="ar"><cfif ar[1] EQ r.area><cfset arName = ar[2]></cfif></cfloop>
        <tr class="grp" data-g="#encodeForHTMLAttribute(key)#"><td colspan="2">#encodeForHTML(arName)##len(r.grp ?: "") ? " › " & encodeForHTML(r.grp) : ""#</td>
            <td><cfif canEdit><select class="bulk" data-col="g" style="width:auto;font-size:12px"><option value="-">set all…</option><option value="">Inherit</option><cfloop list="#MODES#" item="m"><option value="#m#">#LBL[m]#</option></cfloop></select></cfif></td>
            <td><cfif canEdit><select class="bulk" data-col="e" style="width:auto;font-size:12px"><option value="-">set all…</option><option value="">Inherit</option><cfloop list="#MODES#" item="m"><option value="#m#">#LBL[m]#</option></cfloop></select></cfif></td>
            <td colspan="2"></td></tr>
        <cfset lastKey = key>
    </cfif>
    <cfset arrayAppend(ids, r.id)>
    <cfset unsafe = listFind("boxwide,server", r.safety) GT 0>
    <cfset ownKey = len(r.card_key ?: "") ? r.card_key : "pg_" & r.id>
    <tr data-g="#encodeForHTMLAttribute(key)#">
        <td><b>#encodeForHTML(r.label)#</b><div class="mono small muted">#encodeForHTML(r.path)#</div></td>
        <td><cfif canEdit><select name="sf_#r.id#" style="width:auto;font-size:12px"><cfloop list="sandbox,boxwide,server,unknown" item="s"><option value="#s#" #r.safety EQ s ? "selected" : ""#>#s#</option></cfloop></select><cfelse>#safeBadge(r.safety)#</cfif></td>
        <td>#modeSelect("g_" & r.id, r.guided_mode ?: "", r.fg.inherited, unsafe)#<div class="small">now: #effBadge(r.fg)#</div></td>
        <td>#modeSelect("e_" & r.id, r.explorer_mode ?: "", r.fe.inherited, unsafe)#<div class="small">now: #effBadge(r.fe)#</div></td>
        <td><details><summary>#len(r.guard_html ?: "") ? "edit instructions" : "write instructions"#</summary>
                <input type="text" name="gt_#r.id#" value="#encodeForHTMLAttribute(r.guard_title ?: "")#" placeholder="Title (default: You are using: #encodeForHTMLAttribute(r.label)#)" maxlength="160">
                <textarea name="gh_#r.id#" rows="4" placeholder="What the prospect can do here, what to try, what to watch out for (HTML allowed)">#encodeForHTML(r.guard_html ?: "")#</textarea>
                <label style="font-weight:400"><input type="checkbox" name="ro_#r.id#" value="1" #val(r.readonly) ? "checked" : ""#> read-only (no saving on this page)</label>
            </details></td>
        <td class="small"><input type="text" name="ck_#r.id#" value="#encodeForHTMLAttribute(r.card_key ?: "")#" placeholder="group: #encodeForHTMLAttribute(r.fe.key)#" style="width:130px;font-size:12px">
            <div><cfif structKeyExists(ownCards, ownKey)>own card ✓ <a href="/ain5py/addon.cfm?a=demo&p=library">edit</a><cfelse><a href="/ain5py/addon.cfm?a=demo&p=library&new=1&feature=#encodeForURL(ownKey)#" title="Write a card for this page, then put #encodeForHTMLAttribute(ownKey)# in the box">write its own card</a></cfif></div></td>
    </tr>
</cfloop>
</table>
<input type="hidden" name="ids" value="#arrayToList(ids)#">
<cfif canEdit><div class="savebar"><button class="btn primary">Save the changes</button><span class="muted small" id="amDirty"></span></div></cfif>
</form>
<script>
(function () {
  var f = document.getElementById("amForm"), n = document.getElementById("amDirty");
  function count() { var c = f.querySelectorAll(".changed").length; if (n) n.textContent = c ? c + " change(s) not saved yet" : ""; }
  f.addEventListener("change", function (e) {
    var s = e.target;
    if (s.classList.contains("bulk")) {
      var col = s.dataset.col, v = s.value, g = s.closest("tr").dataset.g;
      if (v === "-") return;
      f.querySelectorAll('tr[data-g="' + CSS.escape(g) + '"] select[name^="' + col + '_"]').forEach(function (x) {
        var opt = x.querySelector('option[value="' + v + '"]');
        if (opt && !opt.disabled) { x.value = v; x.classList.toggle("changed", x.value !== x.dataset.cur); }
      });
      s.value = "-"; count(); return;
    }
    if (s.classList.contains("msel")) s.classList.toggle("changed", s.value !== s.dataset.cur);
    count();
  });
})();
</script>
</div>
</cfoutput>
