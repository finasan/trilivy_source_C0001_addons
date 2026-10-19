<!--- asset - the add-on's static files (assets/), which nginx never serves directly. --->
<cfset f = url.f ?: "">
<cfset types = {"demo.js": "application/javascript; charset=utf-8", "demo.css": "text/css; charset=utf-8"}>
<cfif NOT structKeyExists(types, f)><cfheader statuscode="404"><cfabort></cfif>
<cfset path = expandPath("/trlvaddons/demo/assets/" & f)>
<cfheader name="Cache-Control" value="private, max-age=300">
<cfcontent type="#types[f]#" file="#path#" reset="true">
