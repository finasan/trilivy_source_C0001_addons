#!/usr/bin/env python3
"""Demo add-on timer -> the add-on's housekeeping page (pages/cron.cfm).

Signs in over loopback (Lucee :8888, no nginx) as the add-on's system operator,
whose password bootstrap keeps in /etc/trilivy/addon_demo_svc.env, then calls
/ain5py/addon_api.cfm?a=demo&p=cron&job=<hourly|daily> and prints its report.
"""
import http.cookiejar
import json
import sys
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8888"
ENV = "/etc/trilivy/addon_demo_svc.env"


def main(job: str) -> int:
    env = {}
    with open(ENV, encoding="utf-8") as fh:
        for line in fh:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = v
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    op.open(BASE + "/ain5py/login/login.cfm", timeout=60).read()
    data = urllib.parse.urlencode({"email": env["DEMO_SVC_EMAIL"], "password": env["DEMO_SVC_PASSWORD"]}).encode()
    op.open(BASE + "/ain5py/login/login.cfm", data=data, timeout=60).read()
    r = op.open(f"{BASE}/ain5py/addon_api.cfm?a=demo&p=cron&job={urllib.parse.quote(job)}", timeout=600)
    body = r.read().decode("utf-8", "replace")
    try:
        rep = json.loads(body)
    except ValueError:
        print("cron: not JSON (sign-in failed?): " + body[:300], file=sys.stderr)
        return 2
    print(json.dumps(rep))
    op.open(BASE + "/ain5py/login/logout.cfm", timeout=30).read()
    return 1 if rep.get("errors") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "hourly"))
