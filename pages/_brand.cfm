<!--- The platform's look for every demo page: brand colour tokens and the IBM
      Plex Sans font the main panel pages load. The shared header (login/header.cfm)
      sets no font of its own, so without this the whole page - header included -
      fell back to the browser default (Times New Roman). Included once per page. --->
<cfif NOT structKeyExists(request, "demoBrandDone")>
    <cfset request.demoBrandDone = true>
    <cfinclude template="/ain5py/assets/brand_tokens.cfm">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>body{font-family:var(--fs);}</style>
</cfif>
