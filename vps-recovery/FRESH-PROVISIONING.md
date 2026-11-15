# Fresh VPS provisioning: keys first, security layers second

**Status: source published for review. Not integration-tested on the user's VPS.** Designed for fresh Ubuntu 24.04/26.04. Do not run on a system you need to preserve without a snapshot. This file is NOT the previous VPS recovery installer.

## Architecture and security boundary
1. Log timestamp, last logins and sshd events before changes.
2. Generate an Ed25519 SSH keypair in a root-restricted directory; append ONLY its public key to root authorized_keys. Never replace preexisting authorized keys automatically.
3. Install packages from configured Ubuntu apt sources: OpenSSH, UFW, Fail2Ban, nftables, auditd, AppArmor tools, AIDE, unattended upgrades and Python crypto. Package bootstrap temporarily requires outbound internet.
4. Encrypt a temporary tar archive containing the SSH private and public keys with independent AES-256-GCM + scrypt. Print the unlock secret to the physical provider console ONLY, bypassing redirected logs.
5. Try ffsend (snap upstream package if available), upload encrypted package to Send with 1 download and 1-hour expiry. Save its link locally. If ffsend not available, the handoff fails safely and automatic password lockdown is deferred.
6. Start sshd and show server SSH host fingerprint for out-of-band verification.
7. **Mandatory manual gate:** independently download archive, decrypt on your own trusted client, verify private/public match and verify a fresh SSH key connection from a second device. Type VERIFIED-KEY-LOGIN only after verifying. If gate skipped, SSH password disablement is deferred, and the script logs warning. It doesn't manufacture this proof.
8. Disable SSH password and keyboard-interactive authentication, leaving root key authentication temporarily possible. Verify effective sshd settings.
9. Configure Fail2Ban sshd jail, auditd, persistent journaling, update timer (downloads require a future approved maintenance window), AppArmor checks, AIDE package only (do not trust baseline before inspection), CrowdSec detection if packaged, local health timer, systemd hardening example.
10. Enable UFW with default deny incoming/outgoing. Permit temporary public inbound SSH **only if a genuine key login is confirmed and SSH password authentication is verified disabled**. Otherwise **no inbound SSH exception**: provider console recovery is required. Never restrict TCP 22 to VPN until VPN access is tested.
11. Print PASS/FAIL per step and local logs. Failures don't silently claim success. **The firewall step still runs after an earlier noncritical failure. It intentionally fails closed: without verified key-only login, inbound SSH remains blocked and only the provider console can complete the handoff. Independently verify provider console access and a snapshot beforehand.**

## Private key handoff risks
- **Never paste a private key or the unlock secret into edutho.in/Kennynote**. The note is an anonymous shareable web document, not a trusted secret-management vault.
- Posting the one-time link publicly is not recommended: anyone who consumes it first can burn the only download, even though the separately encrypted bundle protects the key's contents.
- **A single-use link is usable by only one downloader.** If you use it on your laptop, ChatGPT Work/Gateway cannot download the same link later. For agent access, provision a distinct, individually revocable public key and use an authorized, auditable private key management integration.
- The installation script does **not** write to Edutho. There is no verified authenticated API/UI automation available for that website here.
- The separate unlock secret is shown only to the provider console and is not saved in the bootstrap log. Keep it offline. The encrypted package stays under /root/vps-bootstrap.
- A plain SSH private key exists on the VPS during generation until remote access is verified; then it is deleted normally (not a guaranteed forensic wipe on SSD/storage snapshots). Creating a key on a client instead of the server would avoid this exposure in future.
- Decrypt the .enc package on a trusted Python host with `python3 decrypt-handoff.py vps-ssh-keys.enc` and `python3-cryptography`. Then extract the .tar.gz into a private directory with umask 077.

## Cautions
- All actions assume a trusted OS image. Host-level snapshot and provider-side firewall are best set before internet exposure.
- Root SSH remains enabled for key authentication until a separate sudo administrator account has a verified login.
- The strict outbound firewall prevents future DNS requests, package downloads, CrowdSec global feeds, alerts, and remote monitoring agents unless explicit exceptions are approved.
- OpenSnitch requires a tested authenticated remote GUI before active per-connection approval. Its rules cannot bypass UFW outbound drops. It is not silently activated.
- Cloudflare Access, Tailscale/WireGuard, remote logging, provider firewall, non-root administrator, hardware-key MFA and AEGIS require separate actions.
- Reboot recovery and an actual remote SSH login are required before treating the install as secure.
- Do NOT delete or burn the only key backup before confirming a working private key on a trusted independent device.

## Console use
Download the script from a **pinned GitHub commit** (not mutable main), review it, validate Bash syntax with `bash -n`, then execute with `bash` as root.

## Logs
- `/var/log/vps-bootstrap/<timestamp>.log`
- `/var/log/vps-bootstrap/summary.txt`
- `/var/log/vps-bootstrap/health-last.txt`

Before booting a replacement instance, use the provider's edge firewall to restrict administrative access if available; this script cannot protect the period before it starts. Do not confuse successful package installation with proof the VPS was never compromised.
