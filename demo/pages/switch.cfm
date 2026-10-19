<!--- switch - the prospect's own Guided / Full platform switch (DEMO bar and demo
      home). POST only, with the session token printed in those forms. --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)><cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false"></cfif>
<cfif cgi.request_method EQ "POST" AND len(session.demo_swtok ?: "") AND (form.t ?: "") EQ session.demo_swtok>
    <cfset nm = demo.setMode(d.pid, form.mode ?: "", "prospect")>
    <cfset demo.sessionDemo(true)>
    <cflocation url="#nm EQ 'explorer' ? '/ain5py/menucenter/index_v2.cfm' : '/ain5py/addon.cfm?a=demo&p=welcome'#" addtoken="false">
</cfif>
<cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
