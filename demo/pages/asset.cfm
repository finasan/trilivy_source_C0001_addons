<!--- asset - the add-on's static files (assets/), which nginx never serves directly. --->
<cfset f = url.f ?: "">
<cfset types = {"demo.js": "application/javascript; charset=utf-8", "demo.css": "text/css; charset=utf-8", "sample_docs.zip": "application/zip"}>
<cfif NOT structKeyExists(types, f)><cfheader statuscode="404"><cfabort></cfif>
<cfset path = expandPath("/trlvaddons/demo/assets/" & f)>
<!--- the Quick Start's sample documents (assets/samples/*.md), zipped on first use --->
<cfif f EQ "sample_docs.zip">
    <cfset src = expandPath("/trlvaddons/demo/assets/samples")>
    <cfset path = getTempDirectory() & "trlv_demo_sample_docs.zip">
    <cfif NOT fileExists(path) OR dateDiff("s", getFileInfo(path).lastModified, getFileInfo(src).lastModified) GT 0>
        <cfzip action="zip" file="#path#" source="#src#" overwrite="true">
    </cfif>
    <cfheader name="Content-Disposition" value='attachment; filename="Brightwater_sample_documents.zip"'>
</cfif>
<cfheader name="Cache-Control" value="private, max-age=300">
<cfcontent type="#types[f]#" file="#path#" reset="true">
