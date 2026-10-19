<cfset activeTab = "codes">
<cfinclude template="_ui.cfm">
<!--- Menu codes (2026-10-19) - item by item, what a FULL PLATFORM prospect gets in
      the menus drawn by menugen (Manage, Knowledge, Quick) and the Instance menu:
        SPT  the group's sales card, on the group and on everything below it without a code of its own
        SPS  the item's own card (locked)
        SPO  the item's own card with "Open it now" (then the real page works)
        OPE  open, no card
        HID  removed from the menu; its address says "not part of the demo"
      An item without a code takes its nearest ancestor's code and card. The code
      belongs to the menu POSITION (cx_demo_nodes, keyed by trail): the same page
      can be SPO in one place and SPS in another; its address (opened directly)
      follows the most open of them. A box-wide or server page never opens. --->
<cfset msg = ""><cfset msgKind = "ok">
<cfset canEdit = listFind("admin,se", op.role) GT 0>
<cfset CODES = "SPT,SPS,SPO,OPE,HID">
<cfset CODE_LBL = {SPT: "SPT · group card, inherited", SPS: "SPS · own card (locked)", SPO: "SPO · card + Open it now", OPE: "OPE · open", HID: "HID · hidden"}>
<cfset AREA_OK = {manage: "Manage menu", kb: "Knowledge menu", quick: "Quick menu", instance: "Instance menu"}>
<cfset PREFIX = {manage: "mg", kb: "kb", quick: "qk", instance: "ic"}>
<cfparam name="url.area" default="manage">
<cfif NOT structKeyExists(AREA_OK, url.area)><cfset url.area = "manage"></cfif>
<cfset area = url.area>

<cfscript>
    function norm(string s) {
        return trim(reReplace(reReplace(lCase(arguments.s), "[^a-z0-9 ]", " ", "all"), "\s+", " ", "all"));
    }
    /** A card key for a node: <prefix>_<words of its trail>, at most 60 characters. */
    function autoKey(string trail) {
        var w = reReplace(norm(replace(arguments.trail, " › ", " ", "all")), " ", "_", "all");
        return left(PREFIX[area] & "_" & w, 60);
    }
    /** "Label - CODE" lines: [{label, code, line}] (code "" = no code given). */
    function parseList(string txt) {
        var out = [];
        var i = 0;
        for (var ln in listToArray(replace(arguments.txt, chr(13), "", "all"), chr(10))) {
            i++;
            var t = trim(ln);
            if (!len(t)) continue;
            var m = reFindNoCase("^(.*?)[\s\-–—:]+(SPT|SPS|SPO|OPE|HID)\s*$", t, 1, true);
            if (m.pos[1]) arrayAppend(out, {label: trim(mid(t, m.pos[2], m.len[2])), code: uCase(mid(t, m.pos[3], m.len[3])), line: i});
            else arrayAppend(out, {label: t, code: "", line: i});
        }
        return out;
    }
    /** Matches the pasted lines to the nodes in menu order (a repeated label takes the next one). */
    function matchList(array lines, array nodes) {
        var res = {hits: [], misses: []};
        var at = 1;
        for (var l in arguments.lines) {
            var want = norm(l.label);
            var found = 0;
            for (var pass = 1; pass LTE 2 && !found; pass++) {
                var from = pass == 1 ? at : 1;
                for (var j = from; j LTE arrayLen(arguments.nodes); j++) {
                    var have = norm(arguments.nodes[j].label);
                    var ok = have == want || (len(want) GTE 6 && (left(have, len(want)) == want || left(want, len(have)) == have));
                    if (ok && !arrayFind(res.hits.map(function(h) { return h.idx; }), j)) { found = j; break; }
                }
            }
            if (found) { arrayAppend(res.hits, {idx: found, node: arguments.nodes[found], code: l.code, line: l.line, label: l.label}); at = found + 1; }
            else arrayAppend(res.misses, l);
        }
        return res;
    }
</cfscript>

<cfset nodesQ = queryExecute("SELECT * FROM cx_demo_nodes WHERE area = :a ORDER BY sort, id", {a: area}, {datasource: "addon_demo"})>
<cfset nodes = []><cfloop query="nodesQ"><cfset arrayAppend(nodes, queryGetRow(nodesQ, nodesQ.currentRow))></cfloop>
<cfset preview = {}>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif NOT canEdit><cfthrow message="Only operators with role admin or se can change the menu codes."></cfif>
        <cfswitch expression="#form.action ?: ''#">
            <cfcase value="scan">
                <cfset r = demo.scanMenus(area)>
                <cfset msg = "Menu scanned: " & (r[area] ?: "?") & (isNumeric(r[area] ?: "") ? " links." : "")>
                <cfif NOT isNumeric(r[area] ?: "")><cfset msgKind = "warn"></cfif>
            </cfcase>
            <cfcase value="save">
                <cfset changed = 0>
                <cfloop array="#nodes#" item="n">
                    <cfif NOT structKeyExists(form, "c_#n.id#")><cfcontinue></cfif>
                    <cfset c = uCase(form["c_#n.id#"])><cfif NOT listFind(CODES, c)><cfset c = ""></cfif>
                    <cfset k = left(reReplace(lCase(form["k_#n.id#"] ?: ""), "[^a-z0-9_]", "", "all"), 60)>
                    <cfif c NEQ (n.code ?: "") OR k NEQ (n.card_key ?: "")>
                        <cfset queryExecute("UPDATE cx_demo_nodes SET code = :c, card_key = :k, updated_by = :by WHERE id = :id", {
                            c: {value: c, null: NOT len(c)}, k: {value: k, null: NOT len(k)}, by: op.email ?: op.oid, id: {value: n.id, cfsqltype: "cf_sql_integer"}
                        }, {datasource: "addon_demo"})>
                        <cfset changed++>
                    </cfif>
                </cfloop>
                <cfset demo.pagesChanged()>
                <cfset msg = changed & " item(s) saved. Full-platform prospects get the change within a minute.">
            </cfcase>
            <cfcase value="paste,paste_apply">
                <cfset lines = parseList(form.list ?: "")>
                <cfset m = matchList(lines, nodes)>
                <cfif form.action EQ "paste">
                    <cfset preview = {list: form.list ?: "", m: m, clear: (form.clear ?: "") EQ "1"}>
                <cfelse>
                    <cfset clr = (form.clear ?: "") EQ "1">
                    <cfset changed = 0>
                    <cfloop array="#m.hits#" item="h">
                        <cfif NOT len(h.code) AND NOT clr><cfcontinue></cfif>
                        <cfset k = h.node.card_key ?: "">
                        <cfif NOT len(k) AND listFind("SPT,SPS,SPO", h.code)><cfset k = autoKey(h.node.trail)></cfif>
                        <cfset queryExecute("UPDATE cx_demo_nodes SET code = :c, card_key = :k, updated_by = :by WHERE id = :id", {
                            c: {value: h.code, null: NOT len(h.code)}, k: {value: k, null: NOT len(k)}, by: op.email ?: op.oid,
                            id: {value: h.node.id, cfsqltype: "cf_sql_integer"}}, {datasource: "addon_demo"})>
                        <cfset changed++>
                    </cfloop>
                    <cfset demo.pagesChanged()>
                    <cfset msg = changed & " item(s) set from the list." & (arrayLen(m.misses) ? " Not found in the menu: " & arrayLen(m.misses) & " line(s)." : "")>
                    <cfif arrayLen(m.misses)><cfset msgKind = "warn"></cfif>
                </cfif>
            </cfcase>
        </cfswitch>
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
    <cfset nodesQ = queryExecute("SELECT * FROM cx_demo_nodes WHERE area = :a ORDER BY sort, id", {a: area}, {datasource: "addon_demo"})>
    <cfset nodes = []><cfloop query="nodesQ"><cfset arrayAppend(nodes, queryGetRow(nodesQ, nodesQ.currentRow))></cfloop>
</cfif>

<cfset nm = demo.nodeMap()>
<cfset tree = nm.byArea[area] ?: {}>
<cfset cards = {}>
<cfset qc = queryExecute("SELECT feature_key, GROUP_CONCAT(DISTINCT audience ORDER BY audience) AS aud FROM cx_demo_pitch WHERE status <> 'retired' GROUP BY feature_key", {}, {datasource: "addon_demo"})>
<cfloop query="qc"><cfset cards[qc.feature_key] = qc.aud></cfloop>
<cfset tally = {SPT: 0, SPS: 0, SPO: 0, OPE: 0, HID: 0, none: 0}>
<cfloop array="#nodes#" item="n"><cfset e = tree[n.trail].code ?: ""><cfset tally[len(e) ? e : "none"]++></cfloop>

<cfoutput>
<style>
.mc .areas{display:flex;gap:6px;flex-wrap:wrap;margin:0 0 12px}
.mc .areas a{padding:6px 12px;border-radius:999px;border:1px solid ##c9d2e3;text-decoration:none;color:##1b2333;font-weight:600;font-size:13px}
.mc .areas a.on{background:##2457d6;border-color:##2457d6;color:##fff}
.mc .legend{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:8px;margin:0 0 14px}
.mc .legend div{border:1px solid ##e3e7ef;border-radius:10px;padding:8px 10px;font-size:12.5px;background:##fff}
.mc .cd{display:inline-block;font:700 11px/1 ui-monospace,Consolas,monospace;padding:4px 7px;border-radius:5px;white-space:nowrap}
.mc .cd.SPT{background:##efe9fb;color:##6b46c1}.mc .cd.SPS{background:##e8eefc;color:##2457d6}.mc .cd.SPO{background:##e3f5f5;color:##0f7f7f}
.mc .cd.OPE{background:##e3f5ee;color:##11845b}.mc .cd.HID{background:##f1f3f8;color:##5d6779}.mc .cd.inh{background:none;border:1px dashed ##c9d2e3;color:##5d6779}
.mc table.tr{table-layout:fixed}
.mc table.tr td{vertical-align:middle;padding:5px 8px}
.mc tr.grp td{background:##f9fafc}
.mc td.nm{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mc td.nm .p{display:block;font-size:11.5px;color:##5d6779;overflow:hidden;text-overflow:ellipsis}
.mc select,.mc input.k{padding:4px 6px;font-size:12.5px}
.mc .warn{color:##b26a00;font-size:11.5px;font-weight:600}.mc .okc{color:##11845b;font-size:11.5px}
.mc .changed{outline:2px solid ##ffb300;outline-offset:1px}
.mc .savebar{position:sticky;bottom:0;background:##fff;border-top:1px solid ##e3e7ef;padding:10px 0;display:flex;gap:10px;align-items:center;z-index:5}
.mc textarea{font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
@media (max-width:900px){.mc table.tr{display:block;overflow-x:auto}}
</style>
<div class="mc">
<h1>Menu codes</h1>
<p class="muted" style="margin-top:-6px">Item by item, what a <b>Full platform</b> prospect gets in this menu. An item without a code takes its nearest group's code
    and card. The code belongs to the <b>place</b> in the menu, so the same page can be open in one place and locked in another; opened by its address,
    a page follows the most open of its places. Pages that show other prospects' data or change the server never open (⚠). Guided does not show these menus.</p>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<div class="areas">
    <cfloop collection="#AREA_OK#" item="ak"><a href="/ain5py/addon.cfm?a=demo&p=codes&area=#ak#" class="#ak EQ area ? 'on' : ''#">#AREA_OK[ak]#</a></cfloop>
</div>
<div class="legend">
    <cfloop list="#CODES#" item="c"><div><span class="cd #c#">#c#</span> #encodeForHTML(listRest(CODE_LBL[c], "·"))# · <b>#tally[c]#</b></div></cfloop>
    <div><span class="cd inh">none</span> feature map / Access map · <b>#tally.none#</b></div>
</div>

<cfif NOT arrayLen(nodes)>
    <div class="card"><p>This menu has not been read yet.</p>
        <form method="post"><input type="hidden" name="action" value="scan"><button class="btn primary" #canEdit ? "" : "disabled"#>Read the menu now</button></form></div>
<cfelse>
    <details class="card" #structIsEmpty(preview) ? "" : "open"#>
        <summary style="cursor:pointer;font-weight:700">Paste a list (Label - CODE, one per line, in menu order)</summary>
        <form method="post" style="margin-top:10px">
            <textarea name="list" rows="10" placeholder="Users - SPT&##10;Manage - SPS&##10;View Log - HID&##10;Instances - SPT&##10;Manage Triade">#encodeForHTML(preview.list ?: "")#</textarea>
            <label style="font-weight:400"><input type="checkbox" name="clear" value="1" #(preview.clear ?: true) ? "checked" : ""#> a line without a code clears that item's code (it inherits)</label>
            <div style="display:flex;gap:8px;margin-top:8px">
                <button class="btn" name="action" value="paste" #canEdit ? "" : "disabled"#>Preview</button>
                <cfif NOT structIsEmpty(preview)><button class="btn primary" name="action" value="paste_apply" #canEdit ? "" : "disabled"#>Apply #arrayLen(preview.m.hits)# line(s)</button></cfif>
            </div>
        </form>
        <cfif NOT structIsEmpty(preview)>
            <table><tr><th>Line</th><th>You wrote</th><th>Menu item</th><th>Code</th></tr>
            <cfloop array="#preview.m.hits#" item="h"><tr><td>#h.line#</td><td>#encodeForHTML(h.label)#</td><td class="small">#encodeForHTML(h.node.trail)#</td>
                <td><cfif len(h.code)><span class="cd #h.code#">#h.code#</span><cfelse><span class="cd inh">#preview.clear ? "clear" : "keep"#</span></cfif></td></tr></cfloop>
            <cfloop array="#preview.m.misses#" item="x"><tr><td>#x.line#</td><td>#encodeForHTML(x.label)#</td><td class="warn" colspan="2">not found in this menu</td></tr></cfloop>
            </table>
        </cfif>
    </details>

    <form method="post" id="mcForm">
    <input type="hidden" name="action" value="save">
    <table class="tr">
        <colgroup><col style="width:34%"><col style="width:17%"><col style="width:19%"><col style="width:30%"></colgroup>
        <tr><th>Menu item</th><th>Code</th><th>Card</th><th>Prospect gets</th></tr>
        <cfloop array="#nodes#" item="n">
            <cfset e = tree[n.trail] ?: {code: "", card: "", from: ""}>
            <cfset row = len(n.path ?: "") ? demo.pageRow(n.path) : {}>
            <cfset unsafe = listFind("boxwide,server", row.safety ?: "") GT 0>
            <cfset effMode = len(e.code) ? demo.codeMode(e.code) : "">
            <cfset blocked = unsafe AND listFind("open,guard", effMode) AND n.kind EQ "link">
            <tr class="#n.kind EQ 'group' ? 'grp' : ''#">
                <td class="nm" style="padding-left:#8 + (n.depth - 1) * 20#px" title="#encodeForHTMLAttribute(n.trail)#">
                    #n.kind EQ "group" ? "▸ <b>" & encodeForHTML(n.label) & "</b>" : encodeForHTML(n.label)#
                    <cfif n.kind EQ "link"><span class="p">#len(n.path ?: "") ? encodeForHTML(n.path) : "(leaves the box)"#<cfif len(row.safety ?: "")> · #row.safety#</cfif></span></cfif>
                </td>
                <td><select name="c_#n.id#" class="csel" data-cur="#n.code ?: ''#" #canEdit ? "" : "disabled"#>
                    <option value="">— inherit</option>
                    <cfloop list="#CODES#" item="c"><option value="#c#" #(n.code ?: "") EQ c ? "selected" : ""#>#c#</option></cfloop>
                </select></td>
                <td><input type="text" class="k" name="k_#n.id#" value="#encodeForHTMLAttribute(n.card_key ?: '')#" data-cur="#encodeForHTMLAttribute(n.card_key ?: '')#"
                        placeholder="#encodeForHTMLAttribute(len(n.code ?: '') ? autoKey(n.trail) : 'card key')#" maxlength="60" #canEdit ? "" : "disabled"#></td>
                <td>
                    <cfif len(e.code)>
                        <span class="cd #e.code#">#e.code#</span>
                        <cfif e.from NEQ n.trail><span class="small muted">from #encodeForHTML(listLast(e.from, "›"))#</span></cfif>
                        <cfif blocked><div class="warn">⚠ #row.safety#: shows its card until the page is made safe</div></cfif>
                        <cfif listFind("SPT,SPS,SPO", e.code) AND (e.from EQ n.trail OR n.kind EQ "link")>
                            <cfif structKeyExists(cards, e.card)><div class="okc">card #encodeForHTML(e.card)# ✓ (#cards[e.card]#)</div>
                            <cfelse><div class="warn">no card #encodeForHTML(e.card)# yet: <a href="/ain5py/addon.cfm?a=demo&p=library&new=1&feature=#encodeForURL(e.card)#">write it</a> (else the feature card shows)</div></cfif>
                        </cfif>
                    <cfelse>
                        <span class="cd inh">none</span> <span class="small muted">feature map / Access map</span>
                    </cfif>
                </td>
            </tr>
        </cfloop>
    </table>
    <cfif canEdit><div class="savebar"><button class="btn primary">Save the codes</button>
        <span class="muted small" id="mcDirty"></span></div></cfif>
    </form>
    <form method="post" style="margin-top:10px"><input type="hidden" name="action" value="scan"><button class="btn" #canEdit ? "" : "disabled"#>Read the menu again</button>
        <span class="small muted">new items appear here with no code (they inherit their group's)</span></form>
</cfif>
</div>
<script>
(function () {
  var f = document.getElementById("mcForm"), n = document.getElementById("mcDirty");
  if (!f) return;
  function upd(e) {
    var x = e.target;
    if (!x.matches("select.csel, input.k")) return;
    x.classList.toggle("changed", x.value !== (x.dataset.cur || ""));
    var c = f.querySelectorAll(".changed").length;
    if (n) n.textContent = c ? c + " change(s) not saved yet" : "";
  }
  f.addEventListener("change", upd); f.addEventListener("input", upd);
})();
</script>
</div>
</cfoutput>
