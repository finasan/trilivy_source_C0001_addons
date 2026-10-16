<cfset activeTab = "access">
<cfinclude template="_ui.cfm">
<!--- Access map - page by page, what a prospect gets in each experience:
      Open, Open + guardrail (instructions popup, optional read-only), Locked
      (sales popup: the page's own card, else its group's) or Hidden (out of the
      menus). Empty = inherit from the feature map. Pages come from the platform
      menus (each section is scanned on its own) and from pages prospects open.
      The safety label comes from the two-marker audit: a page that shows other
      prospects' data or changes the server is never opened, whatever is chosen here.
      2026-10-16: organised by section (the menu each page comes from) with the
      menu's own groups; Instance menu (Instance Control Panel) added. --->
<cfset msg = ""><cfset msgKind = "ok"><cfset problems = []>
<cfset canEdit = listFind("admin,se", op.role) GT 0>
<cfset MODES = "open,guard,pitch,hidden">
<cfset LBL = {open: "Open", guard: "Open + guardrail", pitch: "Locked (popup)", hidden: "Hidden", capped: "Open (limits)"}>
<cfset AREAS = demo.areas()>
<cfset AREA_KEYS = []><cfloop array="#AREAS#" item="ar"><cfset arrayAppend(AREA_KEYS, ar.key)></cfloop>

<cfparam name="url.area" default="">
<cfparam name="url.q" default="">
<cfparam name="url.show" default="">
<cfif len(url.area) AND NOT arrayFind(AREA_KEYS, url.area)><cfset url.area = ""></cfif>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif NOT canEdit><cfthrow message="Only operators with role admin or se can change the Access map."></cfif>
        <cfif (form.action ?: "") EQ "scan">
            <cfset only = arrayFind(AREA_KEYS, form.area ?: "") ? form.area : "">
            <cfset r = demo.scanMenus(only)>
            <cfset parts = []><cfset bad = false>
            <cfloop array="#AREAS#" item="ar">
                <cfif structKeyExists(r, ar.key)>
                    <cfset arrayAppend(parts, ar.label & ": " & r[ar.key] & (isNumeric(r[ar.key]) ? " links" : ""))>
                    <cfif NOT isNumeric(r[ar.key])><cfset bad = true></cfif>
                </cfif>
            </cfloop>
            <cfset msg = (len(only) ? "Section scanned. " : "All sections scanned. ") & arrayToList(parts, " · ")>
            <cfif bad><cfset msgKind = "warn"></cfif>
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
                <cfset gh = replace(trim(form["gh_#id#"] ?: ""), chr(13) & chr(10), chr(10), "all")>
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

<!--- Nothing scanned yet (a new box): scan once, so every section has its menu --->
<cfif canEdit AND NOT queryExecute("SELECT COUNT(*) AS n FROM cx_demo_page_links", {}, {datasource: "addon_demo"}).n>
    <cftry><cfset demo.scanMenus()><cfcatch></cfcatch></cftry>
</cfif>
<!--- One setting per page (cx_demo_pages); a page shows in every section whose menu
      links to it (cx_demo_page_links), under that menu's group and label.
      is_gone: a later scan of that section did not find the link (decided in MySQL: one clock). --->
<cfset rows = queryExecute("SELECT p.*, TIMESTAMPDIFF(MINUTE, p.menu_seen_at, NOW()) AS seen_mins FROM cx_demo_pages p", {}, {datasource: "addon_demo"})>
<cfset links = queryExecute("
    SELECT l.area, l.path, l.grp, l.label, l.sort,
           (s.v IS NOT NULL AND l.seen_at < STR_TO_DATE(SUBSTRING_INDEX(s.v, '|', 1), '%Y-%m-%d %H:%i:%s') - INTERVAL 60 SECOND) AS is_gone
    FROM cx_demo_page_links l LEFT JOIN cx_demo_settings s ON s.k = CONCAT('state_scan_', l.area)
    ORDER BY FIELD(l.area, #listQualify(arrayToList(AREA_KEYS), "'")#), l.sort", {}, {datasource: "addon_demo"})>
<cfset ownCards = {}>
<cfset qc = queryExecute("SELECT DISTINCT feature_key FROM cx_demo_pitch WHERE status <> 'retired'", {}, {datasource: "addon_demo"})>
<cfloop query="qc"><cfset ownCards[qc.feature_key] = 1></cfloop>
<cfset scans = {}><cfloop array="#AREAS#" item="ar"><cfset scans[ar.key] = demo.lastScan(ar.key)></cfloop>
<cfset ZERO = {open: 0, capped: 0, guard: 0, pitch: 0, hidden: 0}>
<cfset per = {}><cfset tot = {guided: duplicate(ZERO), explorer: duplicate(ZERO), n: 0}>
<cfloop array="#AREAS#" item="ar"><cfset per[ar.key] = {guided: duplicate(ZERO), explorer: duplicate(ZERO), n: 0, gone: 0, unknown: 0}></cfloop>
<!--- each page once: classified for both experiences --->
<cfset byPath = {}><cfset alsoIn = {}>
<cfloop query="rows">
    <cfset pg = queryGetRow(rows, rows.currentRow)>
    <cfset pg.fg = demo.classify(pg.path, "guided")>
    <cfset pg.fe = demo.classify(pg.path, "explorer")>
    <!--- Full platform keeps every menu item: Hidden works as Locked there --->
    <cfif pg.fe.mode EQ "hidden"><cfset pg.fe.mode = "pitch"><cfset pg.fe.asHidden = true></cfif>
    <cfset pg.chosen = len((pg.guided_mode ?: "") & (pg.explorer_mode ?: "")) GT 0>
    <cfset byPath[pg.path] = pg><cfset alsoIn[pg.path] = []>
    <cfset tot.n++><cfset tot.guided[pg.fg.mode]++><cfset tot.explorer[pg.fe.mode]++>
</cfloop>
<!--- the entries of each section: its menu's links; a page no menu links to stays in its own area --->
<cfset areaLabel = {}><cfloop array="#AREAS#" item="ar"><cfset areaLabel[ar.key] = ar.label></cfloop>
<cfset all = []><cfset linked = {}>
<cfloop query="links">
    <cfif NOT structKeyExists(byPath, links.path) OR NOT structKeyExists(per, links.area)><cfcontinue></cfif>
    <cfset arrayAppend(all, {pg: byPath[links.path], area: links.area, grp: links.grp ?: "", label: links.label, gone: val(links.is_gone) EQ 1})>
    <cfset linked[links.path] = 1>
    <cfif NOT arrayFind(alsoIn[links.path], links.area)><cfset arrayAppend(alsoIn[links.path], links.area)></cfif>
</cfloop>
<cfset scannedArea = {}><cfloop array="#AREAS#" item="ar"><cfset scannedArea[ar.key] = scans[ar.key].ok></cfloop>
<cfloop query="rows">
    <cfif structKeyExists(linked, rows.path)><cfcontinue></cfif>
    <cfset ar_ = structKeyExists(per, rows.area) ? rows.area : "other">
    <!--- a menu page that the last scan of its section did not find --->
    <cfset arrayAppend(all, {pg: byPath[rows.path], area: ar_, grp: rows.grp ?: "", label: rows.label, gone: rows.source EQ "menu" AND scannedArea[ar_]})>
    <cfset arrayAppend(alsoIn[rows.path], ar_)>
</cfloop>
<cfloop array="#all#" item="en">
    <cfset pa = per[en.area]>
    <cfset pa.n++><cfset pa.guided[en.pg.fg.mode]++><cfset pa.explorer[en.pg.fe.mode]++>
    <cfif en.gone><cfset pa.gone++></cfif>
    <cfif en.pg.safety EQ "unknown"><cfset pa.unknown++></cfif>
</cfloop>
<!--- the section shown: the chosen one, else the first with pages; a search looks everywhere --->
<cfset searching = len(trim(url.q)) GT 0>
<cfif NOT len(url.area)>
    <cfloop array="#AREAS#" item="ar"><cfif per[ar.key].n><cfset url.area = ar.key><cfbreak></cfif></cfloop>
    <cfif NOT len(url.area)><cfset url.area = AREAS[1].key></cfif>
</cfif>
<cfset curArea = AREAS[1]><cfloop array="#AREAS#" item="ar"><cfif ar.key EQ url.area><cfset curArea = ar></cfif></cfloop>
<cfset list = []><cfset shown = {}>
<cfloop array="#all#" item="en">
    <cfif NOT searching AND en.area NEQ url.area><cfcontinue></cfif>
    <!--- a search shows each page once (its first section) --->
    <cfif searching AND (structKeyExists(shown, en.pg.path) OR NOT findNoCase(trim(url.q), en.label & " " & en.pg.label & " " & en.pg.path & " " & en.grp))><cfcontinue></cfif>
    <cfset r = structCopy(en.pg)>
    <cfset r.area = en.area><cfset r.grp = en.grp><cfset r.label = en.label><cfset r.gone = en.gone>
    <cfset r.others = []>
    <cfloop array="#alsoIn[r.path]#" item="oa"><cfif oa NEQ en.area><cfset arrayAppend(r.others, areaLabel[oa])></cfif></cfloop>
    <cfif url.show EQ "set" AND NOT r.chosen><cfcontinue></cfif>
    <cfif url.show EQ "fullopen" AND NOT listFind("open,capped,guard", r.fe.mode)><cfcontinue></cfif>
    <cfif url.show EQ "unknown" AND r.safety NEQ "unknown"><cfcontinue></cfif>
    <cfif url.show EQ "unsafe" AND NOT listFind("boxwide,server", r.safety)><cfcontinue></cfif>
    <cfif url.show EQ "gone" AND NOT r.gone><cfcontinue></cfif>
    <cfset shown[r.path] = 1>
    <cfset arrayAppend(list, r)>
</cfloop>
<!--- rows into the menu's own groups, in menu order --->
<cfset groups = []><cfset gIdx = {}>
<cfloop array="#list#" item="r">
    <cfset gk = r.area & "|" & (r.grp ?: "")>
    <cfif NOT structKeyExists(gIdx, gk)>
        <cfset arName = r.area><cfloop array="#AREAS#" item="ar"><cfif ar.key EQ r.area><cfset arName = ar.label></cfif></cfloop>
        <cfset arrayAppend(groups, {key: gk, area: arName, name: len(r.grp ?: "") ? r.grp : "Top level", rows: [], c: {guided: duplicate(ZERO), explorer: duplicate(ZERO)}})>
        <cfset gIdx[gk] = arrayLen(groups)>
    </cfif>
    <cfset gg = groups[gIdx[gk]]>
    <cfset arrayAppend(gg.rows, r)><cfset gg.c.guided[r.fg.mode]++><cfset gg.c.explorer[r.fe.mode]++>
</cfloop>

<cfscript>
    function link(struct over = {}) {
        var p = {area: url.area, show: url.show, q: url.q};
        structAppend(p, arguments.over, true);
        var s = "/ain5py/addon.cfm?a=demo&p=access";
        for (var k in ["area", "show", "q"]) if (len(p[k])) s &= "&" & k & "=" & encodeForURL(p[k]);
        return s;
    }
    function modeSelect(string name, string val, string inherited, boolean locked, string col) {
        var h = '<select name="' & name & '" class="msel m-' & (len(val) ? val : "inh") & '" data-col="' & col & '" data-cur="' & val & '"' & (canEdit ? "" : " disabled") & '>';
        h &= '<option value="">Inherit · ' & LBL[inherited] & '</option>';
        for (var m in listToArray(MODES)) {
            var off = locked && listFind("open,guard", m);
            h &= '<option value="' & m & '"' & (val == m ? " selected" : "") & (off ? " disabled" : "") & '>' & LBL[m] & (off ? " (unsafe)" : "") & '</option>';
        }
        return h & '</select>';
    }
    function effBadge(struct f) {
        var c = {open: "b-green", capped: "b-green", guard: "b-blue", pitch: "b-amber", hidden: "b-grey"};
        var t = LBL[f.mode] & ((f.asHidden ?: false) ? " (set Hidden)" : "");
        return '<span class="dbadge ' & (c[f.mode] ?: "b-grey") & '">' & t & '</span>';
    }
    function bar(struct c, numeric n) {
        if (!n) return '<span class="ambar"></span>';
        var h = '<span class="ambar" title="' & (c.open + c.capped) & ' open · ' & c.guard & ' guardrail · ' & c.pitch & ' locked · ' & c.hidden & ' hidden">';
        for (var x in [["o", c.open + c.capped], ["g", c.guard], ["p", c.pitch], ["h", c.hidden]]) {
            if (x[2]) h &= '<i class="' & x[1] & '" style="width:' & numberFormat(x[2] * 100 / n, "0.0") & '%"></i>';
        }
        return h & '</span>';
    }
    function minsAgo(numeric m) {
        if (m LT 1) return "just now";
        if (m LT 60) return m & " min ago";
        if (m LT 1440) return int(m / 60) & " h ago";
        return int(m / 1440) & " d ago";
    }
    function nums(struct c) {
        return '<span class="amn"><b class="o">' & (c.open + c.capped) & '</b> open · <b class="g">' & c.guard & '</b> guardrail · <b class="p">'
             & c.pitch & '</b> locked · <b class="h">' & c.hidden & '</b> hidden</span>';
    }
</cfscript>

<cfoutput>
<style>
.dc{max-width:1320px}
.am2{display:grid;grid-template-columns:250px minmax(0,1fr);gap:18px;align-items:start}
.am2 .rail{position:sticky;top:10px;border:1px solid ##e3e7ef;border-radius:12px;background:##fff;padding:8px}
.am2 .rail a.sec{display:block;padding:8px 10px;border-radius:9px;text-decoration:none;color:##1b2333;margin:0 0 2px}
.am2 .rail a.sec:hover{background:##f6f7fb}.am2 .rail a.sec.on{background:##e8eefc}
.am2 .rail a.sec .t{display:flex;justify-content:space-between;font-weight:700;font-size:13.5px}
.am2 .rail a.sec .t span{color:##5d6779;font-weight:600}
.am2 .rail a.sec .w{font-size:11.5px;color:##b26a00;margin-top:2px}
.am2 .rail .tot{border-top:1px solid ##e3e7ef;margin-top:6px;padding:10px 6px 4px;font-size:12px}
.am2 .ambar{display:flex;height:6px;border-radius:4px;overflow:hidden;background:##eef1f6;margin-top:5px}
.am2 .ambar i{display:block;height:100%}
.am2 .ambar .o,.am2 b.o{background:##2bb07f;color:##11845b}.am2 .ambar .g{background:##5b8def}.am2 .ambar .p{background:##f0a43a}.am2 .ambar .h{background:##aab3c2}
.am2 b.o{background:none}.am2 b.g{color:##2457d6}.am2 b.p{color:##b26a00}.am2 b.h{color:##5d6779}
.am2 .amn{font-size:12px;color:##5d6779}
.am2 .shead{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-start;justify-content:space-between;margin:0 0 10px}
.am2 .shead h2{margin:0;font-size:20px}
.am2 .xp{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin:0 0 12px}
.am2 .xp .card{margin:0;padding:10px 12px}
.am2 .chips{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:0 0 12px}
.am2 .chips a{padding:4px 11px;border-radius:999px;border:1px solid ##c9d2e3;text-decoration:none;color:##1b2333;font-size:12.5px;font-weight:600}
.am2 .chips a.on{background:##2457d6;border-color:##2457d6;color:##fff}
.am2 .chips form{margin-left:auto;display:flex;gap:6px}
.am2 details.grp{border:1px solid ##e3e7ef;border-radius:12px;background:##fff;margin:0 0 10px}
.am2 details.grp>summary{list-style:none;cursor:pointer;padding:10px 14px;display:flex;flex-wrap:wrap;gap:10px;align-items:center}
.am2 details.grp>summary::-webkit-details-marker{display:none}
.am2 details.grp>summary::before{content:"▸";color:##5d6779;transition:transform .15s}
.am2 details.grp[open]>summary::before{transform:rotate(90deg)}
.am2 details.grp>summary .gn{font-weight:700}.am2 details.grp>summary .ga{color:##5d6779;font-size:12px}
.am2 details.grp>summary .gb{margin-left:auto;min-width:160px}
.am2 .bulk{display:flex;flex-wrap:wrap;gap:12px;align-items:center;padding:6px 14px 8px;border-top:1px solid ##eef1f6;font-size:12.5px;color:##5d6779}
.am2 .bulk select{width:auto;padding:3px 6px;font-size:12.5px}
.am2 table.pg{table-layout:fixed;margin:0}
.am2 table.pg th{background:##f9fafc}
.am2 table.pg td{padding:7px 8px;vertical-align:middle}
.am2 table.pg td.lbl b{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.am2 table.pg td.lbl .mono{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.am2 table.pg select{padding:4px 6px;font-size:12.5px}
.am2 .msel.m-open{border-color:##2bb07f;background:##f1fbf6}.am2 .msel.m-guard{border-color:##5b8def;background:##f2f6ff}
.am2 .msel.m-pitch{border-color:##f0a43a;background:##fff8ec}.am2 .msel.m-hidden{border-color:##aab3c2;background:##f4f5f8}
.am2 .changed{outline:2px solid ##ffb300;outline-offset:1px}
.am2 .now{font-size:11.5px;margin-top:3px}
.am2 .tag{display:inline-block;font-size:10.5px;font-weight:700;padding:0 6px;border-radius:5px;background:##f1f3f8;color:##5d6779;margin-left:4px;vertical-align:1px}
.am2 .tag.gone{background:##fde9e7;color:##c0392b}
.am2 button.more{background:none;border:1px solid ##c9d2e3;border-radius:7px;padding:3px 8px;font-size:12px;cursor:pointer;color:##2457d6;white-space:nowrap}
.am2 tr.drawer td{background:##fafbfe;padding:12px 14px}
.am2 tr.drawer .dg{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:16px}
.am2 tr.drawer label{margin-top:0}
.am2 .savebar{position:sticky;bottom:0;background:##fff;border-top:1px solid ##e3e7ef;padding:10px 0;display:flex;gap:10px;align-items:center;z-index:5}
.am2 .empty{padding:30px;text-align:center;color:##5d6779;border:1px dashed ##c9d2e3;border-radius:12px}
@media (max-width:900px){.am2{grid-template-columns:1fr}.am2 .rail{position:static}.am2 .xp{grid-template-columns:1fr}.am2 tr.drawer .dg{grid-template-columns:1fr}}
</style>
<h1>Access map</h1>
<p class="muted" style="margin-top:-6px">Page by page, what a prospect gets in each experience, organised by the menu each page comes from.
<b>Open</b>: the page works. <b>Open + guardrail</b>: it works, with your instructions in a popup the first time (and a "What can I do here?" button); read-only turns saving off.
<b>Locked</b>: the sales popup (the page's own card, else its group's). <b>Hidden</b>: out of the menus in Guided; in Full platform the menus always stay complete, so Hidden works as Locked there.
<b>Inherit</b> follows the feature map. A page that several menus link to has <b>one</b> setting: it shows in each of those sections (tagged "also in"), and a change in one is a change in all.</p>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>

<div class="am2">
<!--- ============ the sections ============ --->
<nav class="rail" aria-label="Sections">
    <cfloop array="#AREAS#" item="ar">
        <cfset pa = per[ar.key]>
        <a class="sec #(NOT searching AND ar.key EQ url.area) ? 'on' : ''#" href="#link({area: ar.key, q: '', show: ''})#" data-nav="1">
            <div class="t">#encodeForHTML(ar.label)#<span>#pa.n#</span></div>
            #bar(pa.explorer, pa.n)#
            <cfif pa.gone><div class="w">#pa.gone# no longer in the menu</div></cfif>
            <cfif ar.key NEQ "other" AND NOT scans[ar.key].ok><div class="w">not scanned yet</div></cfif>
        </a>
    </cfloop>
    <div class="tot">
        <div class="muted">All sections · #tot.n# pages</div>
        <div style="margin-top:4px"><b>Guided</b> #bar(tot.guided, tot.n)#</div>
        <div style="margin-top:6px"><b>Full platform</b> #bar(tot.explorer, tot.n)#</div>
        <div class="small muted" style="margin-top:6px">bars: <b class="o">open</b> · <b class="g">guardrail</b> · <b class="p">locked</b> · <b class="h">hidden</b></div>
        <form method="post" style="margin:10px 0 0"><input type="hidden" name="action" value="scan"><input type="hidden" name="area" value="">
            <button class="btn" style="width:100%" #canEdit ? "" : "disabled"#>Scan all sections</button></form>
    </div>
</nav>

<!--- ============ the section ============ --->
<main>
    <div class="shead">
        <div>
            <cfif searching>
                <h2>Search: “#encodeForHTML(url.q)#”</h2>
                <div class="small muted">in every section · <a href="#link({q: ''})#" data-nav="1">clear the search</a></div>
            <cfelse>
                <h2>#encodeForHTML(curArea.label)#</h2>
                <div class="small muted">Pages from <span class="mono">#encodeForHTML(curArea.src)#</span>
                    <cfif curArea.key NEQ "other"> · <cfif scans[curArea.key].ok>last scanned #minsAgo(scans[curArea.key].mins)# (#scans[curArea.key].n# links)<cfelse>not scanned yet</cfif></cfif></div>
            </cfif>
        </div>
        <cfif NOT searching AND curArea.key NEQ "other">
            <form method="post" style="margin:0"><input type="hidden" name="action" value="scan"><input type="hidden" name="area" value="#curArea.key#">
                <button class="btn" #canEdit ? "" : "disabled"#>Scan this section</button></form>
        </cfif>
    </div>
    <cfif NOT searching AND curArea.key EQ "instance">
        <div class="note small">The Instance Control Panel (Manage › an instance) opens one instance's own tools. Its sidebar has no menu hook, so in Guided it is not trimmed:
            a Hidden item stays in the sidebar there, and clicking it says "not part of the demo". Every item is still gated when it opens.
            The panel's own sections (Overview, Authoring, Enrollments…) are separate rows here.</div>
    </cfif>
    <cfif NOT searching AND curArea.key EQ "other">
        <div class="note small">Pages a prospect opened that no menu lists (a link inside another page, a bookmark). They are added on their own and stay on Inherit until you choose.</div>
    </cfif>
    <cfif NOT searching>
        <div class="xp">
            <div class="card"><div class="small muted">Guided · #per[curArea.key].n# pages</div>#nums(per[curArea.key].guided)##bar(per[curArea.key].guided, per[curArea.key].n)#</div>
            <div class="card"><div class="small muted">Full platform · #per[curArea.key].n# pages</div>#nums(per[curArea.key].explorer)##bar(per[curArea.key].explorer, per[curArea.key].n)#</div>
        </div>
    </cfif>

    <cfset CHIPS = [["", "All pages"], ["set", "Chosen here"], ["fullopen", "Open in Full platform"], ["unsafe", "Unsafe"], ["unknown", "Not audited"], ["gone", "No longer in the menu"]]>
    <div class="chips">
        <cfloop array="#CHIPS#" item="ch">
            <a href="#link({show: ch[1]})#" class="#url.show EQ ch[1] ? 'on' : ''#" data-nav="1">#ch[2]#</a>
        </cfloop>
        <form method="get" data-nav="1">
            <input type="hidden" name="a" value="demo"><input type="hidden" name="p" value="access">
            <input type="hidden" name="area" value="#encodeForHTMLAttribute(url.area)#"><input type="hidden" name="show" value="#encodeForHTMLAttribute(url.show)#">
            <input type="text" name="q" value="#encodeForHTMLAttribute(url.q)#" placeholder="Search every section" style="width:210px">
            <button class="btn">Search</button>
        </form>
    </div>

    <form method="post" id="amForm">
    <input type="hidden" name="action" value="save">
    <cfset ids = []>
    <cfif NOT arrayLen(groups)>
        <div class="empty"><cfif per[curArea.key].n AND NOT searching>No page in this section matches the filter.<cfelseif searching>Nothing matches the search.<cfelse>No pages yet. <cfif curArea.key NEQ "other">Use <b>Scan this section</b>.</cfif></cfif></div>
    </cfif>
    <cfloop array="#groups#" item="gg">
        <details class="grp" open data-g="#encodeForHTMLAttribute(gg.key)#">
            <summary>
                <span class="gn">#encodeForHTML(gg.name)#</span>
                <cfif searching><span class="ga">#encodeForHTML(gg.area)#</span></cfif>
                <span class="ga">#arrayLen(gg.rows)# page#arrayLen(gg.rows) EQ 1 ? "" : "s"#</span>
                <span class="gb">#bar(gg.c.explorer, arrayLen(gg.rows))#</span>
            </summary>
            <cfif canEdit>
                <div class="bulk">Set the whole group:
                    <span>Guided <select class="bset" data-col="g"><option value="-">choose…</option><option value="">Inherit</option><cfloop list="#MODES#" item="m"><option value="#m#">#LBL[m]#</option></cfloop></select></span>
                    <span>Full platform <select class="bset" data-col="e"><option value="-">choose…</option><option value="">Inherit</option><cfloop list="#MODES#" item="m"><option value="#m#">#LBL[m]#</option></cfloop></select></span>
                    <span class="small">(unsafe pages are skipped for Open)</span>
                </div>
            </cfif>
            <table class="pg">
                <colgroup><col style="width:36%"><col style="width:12%"><col style="width:20%"><col style="width:20%"><col style="width:12%"></colgroup>
                <tr><th>Page</th><th>Safety</th><th>Guided</th><th>Full platform</th><th></th></tr>
                <cfloop array="#gg.rows#" item="r">
                    <cfset arrayAppend(ids, r.id)>
                    <cfset unsafe = listFind("boxwide,server", r.safety) GT 0>
                    <cfset ownKey = len(r.card_key ?: "") ? r.card_key : "pg_" & r.id>
                    <cfset hasGuard = len(r.guard_html ?: "") OR len(r.guard_title ?: "")>
                    <tr>
                        <td class="lbl" title="#encodeForHTMLAttribute(r.label & ' — ' & r.path)#"><b>#encodeForHTML(r.label)#<cfif r.gone><span class="tag gone">no longer in the menu</span></cfif><cfif r.source EQ "seen"><span class="tag">opened by a prospect</span></cfif><cfif arrayLen(r.others)><span class="tag" title="One setting for this page: a change here is a change there too">also in #encodeForHTML(arrayToList(r.others, ", "))#</span></cfif></b>
                            <span class="mono small muted">#encodeForHTML(r.path)#</span></td>
                        <td><cfif canEdit><select name="sf_#r.id#" class="sf" data-cur="#r.safety#"><cfloop list="sandbox,boxwide,server,unknown" item="s"><option value="#s#" #r.safety EQ s ? "selected" : ""#>#s#</option></cfloop></select>
                            <cfelse><span class="dbadge #unsafe ? 'b-red' : (r.safety EQ 'sandbox' ? 'b-green' : 'b-grey')#">#r.safety#</span></cfif></td>
                        <td>#modeSelect("g_" & r.id, r.guided_mode ?: "", r.fg.inherited, unsafe, "g")#<div class="now">now #effBadge(r.fg)#</div></td>
                        <td>#modeSelect("e_" & r.id, r.explorer_mode ?: "", r.fe.inherited EQ "hidden" ? "pitch" : r.fe.inherited, unsafe, "e")#<div class="now">now #effBadge(r.fe)#</div></td>
                        <td><button type="button" class="more" data-id="#r.id#" aria-expanded="false">Details<cfif hasGuard> ✎</cfif><cfif val(r.readonly)> RO</cfif><cfif len(r.card_key ?: "")> 🃏</cfif></button></td>
                    </tr>
                    <tr class="drawer" id="dr_#r.id#" hidden><td colspan="5"><div class="dg">
                        <div>
                            <label>Guardrail instructions (shown with Open + guardrail)</label>
                            <input type="text" name="gt_#r.id#" value="#encodeForHTMLAttribute(r.guard_title ?: "")#" placeholder="Title (default: You are using: #encodeForHTMLAttribute(r.label)#)" maxlength="160">
                            <textarea name="gh_#r.id#" rows="4" style="margin-top:6px" placeholder="What the prospect can do here, what to try, what to watch out for (HTML allowed)">#encodeForHTML(r.guard_html ?: "")#</textarea>
                            <label style="font-weight:400;margin-top:6px"><input type="checkbox" name="ro_#r.id#" value="1" #val(r.readonly) ? "checked" : ""#> read-only (no saving on this page)</label>
                        </div>
                        <div>
                            <label>Sales card when Locked</label>
                            <input type="text" name="ck_#r.id#" value="#encodeForHTMLAttribute(r.card_key ?: "")#" placeholder="group card: #encodeForHTMLAttribute(r.fe.key)#">
                            <div class="small" style="margin-top:4px">Empty = the group's card <span class="mono">#encodeForHTML(r.fe.key)#</span>.
                                <cfif structKeyExists(ownCards, ownKey)><br>Own card ✓ <a href="/ain5py/addon.cfm?a=demo&p=library">edit in the Pitch library</a>
                                <cfelse><br><a href="/ain5py/addon.cfm?a=demo&p=library&new=1&feature=#encodeForURL(ownKey)#">Write its own card</a>, then put <span class="mono">#encodeForHTML(ownKey)#</span> here.</cfif></div>
                            <div class="small muted" style="margin-top:8px">Feature map group: <b>#encodeForHTML(r.fe.label)#</b><br>First seen #dateFormat(r.first_seen, "d mmm yyyy")#<cfif len(r.seen_mins ?: "")> · found in the menu #minsAgo(r.seen_mins)#</cfif><cfif len(r.updated_by ?: "") AND r.updated_by NEQ "seed"><br>Changed by #encodeForHTML(r.updated_by)#</cfif></div>
                        </div>
                    </div></td></tr>
                </cfloop>
            </table>
        </details>
    </cfloop>
    <input type="hidden" name="ids" value="#arrayToList(ids)#">
    <cfif canEdit AND arrayLen(ids)><div class="savebar"><button class="btn primary">Save the changes</button><span class="muted small" id="amDirty"></span></div></cfif>
    </form>
</main>
</div>
<script>
(function () {
  var f = document.getElementById("amForm"), n = document.getElementById("amDirty"), dirty = 0;
  if (!f) return;
  function isChanged(x) {
    if (x.type === "checkbox") return x.checked !== x.defaultChecked;
    if (x.tagName === "SELECT") return x.value !== (x.dataset.cur || "");
    return x.value !== x.defaultValue;
  }
  function paint(x) {
    var c = isChanged(x);
    x.classList.toggle("changed", c);
    if (x.classList.contains("msel")) x.className = x.className.replace(/\bm-\w+/, "m-" + (x.value || "inh"));
    // a changed field inside a closed drawer marks its Details button
    var dr = x.closest("tr.drawer");
    if (dr) {
      var b = f.querySelector('button.more[data-id="' + dr.id.slice(3) + '"]');
      if (b) b.classList.toggle("changed", !!dr.querySelector(".changed"));
    }
  }
  function count() {
    dirty = f.querySelectorAll("select.changed, input.changed, textarea.changed").length;
    if (n) n.textContent = dirty ? dirty + " change(s) not saved yet" : "";
  }
  function onEdit(e) {
    var s = e.target;
    if (s.classList.contains("bset")) {
      var col = s.dataset.col, v = s.value, box = s.closest("details.grp");
      if (v === "-") return;
      box.querySelectorAll('select.msel[data-col="' + col + '"]').forEach(function (x) {
        var opt = x.querySelector('option[value="' + v + '"]');
        if (opt && !opt.disabled) { x.value = v; paint(x); }
      });
      s.value = "-"; count(); return;
    }
    if (s.matches("select, input, textarea")) { paint(s); count(); }
  }
  f.addEventListener("change", onEdit);
  f.addEventListener("input", onEdit);
  f.addEventListener("click", function (e) {
    var b = e.target.closest("button.more");
    if (!b) return;
    var dr = document.getElementById("dr_" + b.dataset.id), open = dr.hidden;
    dr.hidden = !open; b.setAttribute("aria-expanded", open ? "true" : "false");
  });
  var saving = false;
  f.addEventListener("submit", function () { saving = true; });
  // leaving the section (or the page) with unsaved choices asks first
  document.querySelectorAll('[data-nav="1"]').forEach(function (el) {
    el.addEventListener(el.tagName === "FORM" ? "submit" : "click", function (e) {
      if (dirty && !confirm(dirty + " change(s) are not saved yet. Leave without saving?")) e.preventDefault();
      else saving = true;
    });
  });
  window.addEventListener("beforeunload", function (e) { if (dirty && !saving) { e.preventDefault(); e.returnValue = ""; } });
})();
</script>
</div>
</cfoutput>
