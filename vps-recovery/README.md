# VPS recovery and nine-layer hardening (staged)

This branch is a recovery aid for an **Ubuntu VPS**, not evidence that its OS is clean. No installation has been performed on the VPS. Do not reprovision or erase logs before investigating unexpected access. The provider console should be available throughout.

## Safety-critical order
1. Save a provider snapshot if possible and record verified SSH host fingerprint; inspect logs with `bash recover-vps.sh audit`.
2. **Before egress lockdown**, run `bash recover-vps.sh security-prep`. This installs auditd, unattended-upgrades, needrestart and AppArmor utilities; enables persistent journaling and a local five-minute health timer. Its initial baseline is not proof of integrity.
3. Run `bash recover-vps.sh recover`. Installs/starts SSH and Fail2Ban, configures UFW to default DENY incoming, default DENY outgoing, and allows inbound port 22 for emergency recovery. Package bootstrap must succeed BEFORE the outbound deny is applied.
4. From a separate machine, verify public-key SSH access against an independently verified host fingerprint. **Never close the console until verified.**
5. Then run `bash recover-vps.sh lock-ssh` to configure key-only SSH. Re-test in another new connection.
6. Once source IP is known stable and recovery method tested, optionally run `bash recover-vps.sh restrict-ssh` to permit SSH only from that address. Dynamic cellular IPs make this risky.
7. Check `bash recover-vps.sh security-status`, and independently inspect `/var/log/vps-recovery`.

## Screenshots: nine components and current coverage
1. **CrowdSec:** `install-crowdsec` can install the local detection engine ONLY from trusted configured apt repos with packages already cached. **No bouncer is automatically activated**, so no CrowdSec firewall bans are claimed; enable vetted nftables bouncer separately after checking UFW coexistence. Reputation feeds require approved outbound.
2. **Layered firewalls:** UFW on host configured; *provider edge firewall* must be configured through ASCS portal/provider, not a script running inside VM. CrowSec nftables bouncer is a separate reviewed step.
3. **Lock SSH to you:** `restrict-ssh` supports stable IPv4 admin address; Tailscale private networking requires credentials, outbound bootstrap, and independent testing.
4. **Cloudflare Access:** Requires Cloudflare account, identity provider, MFA policy, tunnel/connector and narrowly scoped egress. Not silently installed. Not a substitute for SSH host verification.
5. **SSH key-only:** `lock-ssh` after successful tested access. It disables password and keyboard-interactive auth, but **does not automatically disable root SSH**. Migrate to a separate admin account first.
6. **systemd sandbox:** `systemd-template` generates a commented example for **application services only**, never blanket-apply to sshd/docker/systemd.
7. **auditd:** `security-prep` installs auditd and selected file-change watch rules. auditd does not inherently record *every* command or all reads; it is not an immutable forensic trail. Remote/immutable log forwarding pending.
8. **unattended-upgrades:** Installed/enabled without automatic reboot; **cannot fetch patches while default-deny outbound is active**. Arrange controlled update windows, a trusted cache/mirror, or narrowly scoped outbound rules.
9. **24/7 monitoring:** Local five-minute health timer collects service, listener, disk and firewall status. HAL/Titus monitoring and Dependabot integration are **external projects**, not automatically installed or connected. Dependabot applies to supported GitHub repositories, not live OS packages.

## Deliberately incomplete
- AEGIS verified source/package and independent baseline
- Authenticated OpenSnitch GUI and remote approvals, with policy-layer integration
- Provider firewall, Cloudflare Access, or Tailscale mesh access
- CrowdSec remediation bouncer
- Non-root admin + root SSH disable
- Hardware-key MFA / double-door privileged command gate
- Remote tamper-resistant logging, alert delivery, backup/restore testing
- Exit policy exceptions for necessary DNS, updates, monitoring, time synchronization, APIs, and remote access

**Outbound deny is real**, but it blocks the machine's ability to initiate DNS, package downloads, alerts and updates. Inbound SSH replies typically pass as established traffic. OpenSnitch can *not* override UFW drop decisions. Review exact rules and test on this VPS before considering it production-ready.

Never paste passwords or secret keys into GitHub, terminal captures, or chat. Pin a commit and independently verify source before running it. The script has NOT been end-to-end tested against this VPS.
