<!--- Demo Console - shared look and helpers for the operator pages. --->
<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset op = demo.operator()>
<cfparam name="pageTitle" default="Demo Console">
<cfparam name="activeTab" default="console">
<cfscript>
    function badge(string s) {
        var c = {invited: "b-blue", active: "b-green", expiring: "b-amber", expired: "b-grey", suspended: "b-amber",
                 purged: "b-grey", converted: "b-violet", failed: "b-red", building: "b-blue",
                 hot: "b-red", warm: "b-amber", cold: "b-grey", ok: "b-green", running: "b-blue",
                 rolled_back: "b-amber", skipped: "b-grey", draft: "b-amber", verified: "b-blue", live: "b-green", retired: "b-grey"};
        return '<span class="dbadge ' & (c[s] ?: "b-grey") & '">' & encodeForHTML(s) & '</span>';
    }
    function ago(any d) {
        if (!isDate(d)) return "-";
        var m = dateDiff("n", d, now());
        if (m LT 1) return "just now";
        if (m LT 60) return m & " min ago";
        if (m LT 1440) return int(m / 60) & " h ago";
        return int(m / 1440) & " d ago";
    }
</cfscript>
<cfoutput>
<style>
.dc{font:14px/1.5 var(--fs);color:##1b2333;max-width:1180px;margin:18px auto;padding:0 16px}
.dc h1{font-size:24px;margin:4px 0 14px}.dc h2{font-size:18px;margin:22px 0 8px}.dc h3{font-size:15px;margin:16px 0 6px}
.dc .tabs{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 16px;border-bottom:1px solid ##e3e7ef;padding-bottom:8px}
.dc .tabs a{padding:6px 12px;border-radius:8px;text-decoration:none;color:##2457d6;font-weight:600}
.dc .tabs a.on{background:##e8eefc}
.dc table{width:100%;border-collapse:collapse;margin:6px 0 14px;font-size:13.5px}
.dc th,.dc td{text-align:left;padding:7px 8px;border-bottom:1px solid ##e3e7ef;vertical-align:top}
.dc th{font-size:11.5px;text-transform:uppercase;letter-spacing:.05em;color:##5d6779}
.dc .card{border:1px solid ##e3e7ef;border-radius:12px;padding:14px 16px;margin:0 0 14px;background:##fff}
.dc .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}
.dc .muted{color:##5d6779}.dc .small{font-size:12.5px}
.dc .dbadge{display:inline-block;font-size:11.5px;font-weight:700;padding:1px 9px;border-radius:999px;white-space:nowrap}
.dc .b-blue{background:##e8eefc;color:##2457d6}.dc .b-green{background:##e3f5ee;color:##11845b}.dc .b-amber{background:##fff3df;color:##b26a00}
.dc .b-red{background:##fde9e7;color:##c0392b}.dc .b-grey{background:##f1f3f8;color:##5d6779}.dc .b-violet{background:##efe9fb;color:##6b46c1}
.dc .btn{display:inline-block;padding:7px 14px;border-radius:8px;border:1px solid ##c9d2e3;background:##fff;color:##1b2333;text-decoration:none;font-weight:600;cursor:pointer;font-size:13.5px}
.dc .btn.primary{background:##2457d6;border-color:##2457d6;color:##fff}.dc .btn.danger{border-color:##c0392b;color:##c0392b}
.dc .btn:disabled{opacity:.5;cursor:default}
.dc input[type=text],.dc input[type=email],.dc input[type=number],.dc select,.dc textarea{width:100%;padding:7px 9px;border:1px solid ##c9d2e3;border-radius:8px;font:inherit;box-sizing:border-box}
.dc label{display:block;font-weight:600;font-size:13px;margin:8px 0 3px}
.dc .note{border-left:4px solid ##2457d6;background:##e8eefc;padding:9px 13px;border-radius:0 8px 8px 0;margin:8px 0 12px}
.dc .note.warn{border-color:##b26a00;background:##fff3df}.dc .note.err{border-color:##c0392b;background:##fde9e7}.dc .note.ok{border-color:##11845b;background:##e3f5ee}
.dc .mono{font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
.dc .stat{font-size:26px;font-weight:800;line-height:1.1}
.dc .tl{border-left:2px solid ##e3e7ef;margin-left:6px;padding-left:14px}
.dc .tl .ev{margin:0 0 8px}.dc .tl .t{color:##5d6779;font-size:12px}
.dc pre{white-space:pre-wrap;background:##f6f7fb;padding:8px 10px;border-radius:8px;font-size:12.5px;margin:4px 0}
@media (max-width:760px){.dc table{display:block;overflow-x:auto}}
</style>
<div class="dc">
<div class="tabs">
    <a href="/ain5py/addon.cfm?a=demo&p=console" class="#activeTab EQ 'console' ? 'on' : ''#">Prospects</a>
    <a href="/ain5py/addon.cfm?a=demo&p=new" class="#activeTab EQ 'new' ? 'on' : ''#">+ New prospect</a>
    <a href="/ain5py/addon.cfm?a=demo&p=handoffs" class="#activeTab EQ 'handoffs' ? 'on' : ''#">Contact requests</a>
    <a href="/ain5py/addon.cfm?a=demo&p=library" class="#activeTab EQ 'library' ? 'on' : ''#">Pitch library</a>
    <a href="/ain5py/addon.cfm?a=demo&p=access" class="#activeTab EQ 'access' ? 'on' : ''#">Access map</a>
    <a href="/ain5py/addon.cfm?a=demo&p=codes" class="#activeTab EQ 'codes' ? 'on' : ''#">Menu codes</a>
    <a href="/ain5py/addon.cfm?a=demo&p=stories" class="#activeTab EQ 'stories' ? 'on' : ''#">Stories</a>
    <a href="/ain5py/addon.cfm?a=demo&p=reports" class="#activeTab EQ 'reports' ? 'on' : ''#">Reports</a>
    <a href="/ain5py/addon.cfm?a=demo&p=operators" class="#activeTab EQ 'operators' ? 'on' : ''#">Operators</a>
    <a href="/ain5py/addon.cfm?a=demo&p=package" class="#activeTab EQ 'package' ? 'on' : ''#">Package &amp; settings</a>
    <span class="muted small" style="margin-left:auto;align-self:center">#encodeForHTML(op.name ?: "")# · #encodeForHTML(op.role ?: "")#</span>
</div>
<cfif demo.paused()><div class="note warn"><b>The demo is paused.</b> Prospects see "back in a few minutes". Resume it under Package &amp; settings.</div></cfif>
</cfoutput>
