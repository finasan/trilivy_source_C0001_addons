# VPN and Wi-Fi Troubleshooting Guide

Owner: IT Service Desk · Version: 1.1 · Effective: 2 February 2026

## Networks at a glance

| Network | Who | How to connect |
|---|---|---|
| **BW-Staff** | Employees with company laptops | Automatic, certificate-based. No password. |
| **BW-Guest** | Visitors and personal devices | Daily password from reception. Internet only, 8-hour sessions. |
| **BW-Scan** | Warehouse scanners only | Managed by IT. Never connect a laptop. |

The VPN client is **BW Connect**. Gateway address: `vpn.brightwater.example.com`. Use the VPN whenever you work outside a Brightwater office.

## VPN will not connect

1. Check you have internet access (open any public website).
2. Make sure your laptop date and time are correct. A clock that is more than 5 minutes off breaks the certificate check.
3. Quit BW Connect completely (right-click the tray icon → *Exit*) and start it again.
4. Approve the MFA prompt within **60 seconds**; expired prompts cause error **VPN-401**.
5. Hotel or train networks may block the VPN. Select the profile **BW Connect – Port 443** and try again.
6. Still failing? Restart the laptop, then contact the IT Service Desk.

## Common error codes

- **VPN-401**: MFA not approved or timed out. Retry and approve faster.
- **VPN-403**: Your account is not in the remote-access group. Your manager must request access.
- **VPN-512**: Client is outdated. Update via Software Center.

## Slow VPN

- The VPN is split-tunnel: video calls do not go through it, so call quality issues are usually local Wi-Fi.
- Move closer to your router or use a cable.
- Close large file syncs; the VPN is limited to 50 Mbit/s per user.

## Office Wi-Fi problems

- If BW-Staff does not appear, toggle Wi-Fi off and on, then reboot.
- If BW-Staff connects but shows "No internet", your device certificate may have expired (they renew every 12 months). Connect by cable on any desk dock and wait 10 minutes for renewal.
- Dead zones in warehouses should be reported to Facilities with the aisle number.

## Getting help

IT Service Desk: +31 10 000 0100 (24/7) or servicedesk@brightwater.example.com. Include your laptop asset tag (sticker starting with **BWL-**) and a screenshot of the error.
