<!--- pitch_page - a locked feature opened by its address: the card as a full page.
      The popup (assets/demo.js) renders the same card; this page asks it to open
      the card at once and keeps a plain version for no-JS. --->
<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfset feature = reReplace(lCase(request.addon.arg), "[^a-z0-9_]", "", "all")>
<cfif NOT len(feature)><cfset feature = "platform"></cfif>
<cfset c = demo.cardFor(feature, d.audience ?: "business", d.language ?: "en", reReplace(lCase(url.fb ?: ""), "[^a-z0-9_]", "", "all"))>
<cfoutput>
<div style="font:15px/1.6 var(--fs);color:##1b2333;max-width:760px;margin:30px auto;padding:0 16px">
<cfif structIsEmpty(c)>
    <h1>Part of the full platform</h1><p>This part of Trilivy is not open in the demo. Ask us for a walkthrough.</p>
<cfelse>
    <div class="demo-card-static" data-demo-autoopen="#encodeForHTMLAttribute(feature)#" style="border:1px solid ##e3e7ef;border-radius:14px;overflow:hidden">
        <div style="background:##2457d6;color:##fff;padding:16px 20px">
            <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;font-weight:700;opacity:.85">#encodeForHTML(c.kicker ?: "")##c.isDraft ? " · DRAFT" : ""#</div>
            <div style="font-size:21px;font-weight:700;line-height:1.25">#encodeForHTML(c.headline)#</div>
        </div>
        <div style="padding:16px 20px">
            #c.why_html ?: ""#
            <cfif len(c.how_html ?: "")><h3 style="font-size:15px;margin:14px 0 4px">How it works</h3>#c.how_html#</cfif>
            <cfif arrayLen(c.objections)><h3 style="font-size:15px;margin:14px 0 4px">You might be wondering…</h3>
                <cfloop array="#c.objections#" item="o"><details style="border:1px solid ##e3e7ef;border-radius:8px;padding:8px 12px;margin:6px 0"><summary><b>#encodeForHTML(o.q)#</b></summary><p style="margin:6px 0 0">#encodeForHTML(o.a)#</p></details></cfloop>
            </cfif>
            <cfif len(c.proof_html ?: "")><div style="background:##f6f7fb;border-radius:8px;padding:8px 12px;margin-top:12px">#c.proof_html#</div></cfif>
            <cfif structKeyExists(c, "it")><cfset t = c.it>
                <div style="margin-top:16px;padding:12px 14px;border-left:3px solid ##2457d6;background:##f4f7fd;border-radius:0 8px 8px 0">
                    <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;font-weight:700;color:##2457d6">For IT teams#t.isDraft ? " · DRAFT" : ""#</div>
                    <div style="font-size:17px;font-weight:700;line-height:1.3;margin:2px 0 8px">#encodeForHTML(t.headline)#</div>
                    #t.why_html ?: ""#
                    <cfif len(t.how_html ?: "")><h3 style="font-size:15px;margin:14px 0 4px">How it works</h3>#t.how_html#</cfif>
                    <cfif arrayLen(t.objections)><h3 style="font-size:15px;margin:14px 0 4px">You might be wondering…</h3>
                        <cfloop array="#t.objections#" item="o"><details style="border:1px solid ##e3e7ef;border-radius:8px;padding:8px 12px;margin:6px 0;background:##fff"><summary><b>#encodeForHTML(o.q)#</b></summary><p style="margin:6px 0 0">#encodeForHTML(o.a)#</p></details></cfloop>
                    </cfif>
                    <cfif len(t.proof_html ?: "")><div style="background:##fff;border-radius:8px;padding:8px 12px;margin-top:12px">#t.proof_html#</div></cfif>
                </div>
            </cfif>
        </div>
        <div style="padding:12px 20px;border-top:1px solid ##e3e7ef;display:flex;gap:8px;flex-wrap:wrap">
            <a href="##" data-demo-action="talk" data-demo-feature="#encodeForHTMLAttribute(feature)#" style="background:##2457d6;color:##fff;padding:7px 14px;border-radius:8px;text-decoration:none;font-weight:600">Contact us</a>
            <a href="/ain5py/addon.cfm?a=demo&p=welcome" target="_top" style="margin-left:auto;padding:7px 4px;color:##5d6779">Back to your demo</a>
        </div>
    </div>
</cfif>
</div>
<cfif (url.embed ?: "") EQ "1">#request.addon.hooks.frameScripts()#</cfif>
</cfoutput>
