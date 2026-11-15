# Private SSH over WireGuard: staged deployment plan

## Status
**NOT INSTALLED OR ENFORCED.** The VPS at 64.227.208.169 was previously unreachable on TCP 22. This plan must not remove public SSH until VPN connectivity and backup access are independently verified.

## Product naming
The widely used project is [wg-easy](https://github.com/wg-easy/wg-easy), a Docker-based WireGuard administration UI, not necessarily "easy-wg". Its default sample Compose exposes UDP/51820 and TCP/51821, and Docker-published ports can bypass naive UFW assumptions. Avoid publishing the admin UI; bind it to loopback or to the VPN and independently test the resulting listener/firewall behavior. Use a reviewed, version-pinned official release; don't blindly curl the latest Docker Compose.

## Desired final state
- VPS acts as WireGuard server. Public inbound only selected WireGuard UDP port (e.g., 51820), with provider edge firewall and host firewall aligned.
- SSH listens on a VPN IP/interface, or UFW accepts TCP/22 only **on verified WireGuard interface**. Do not change SSH binding until tunnel is established and tested from two client sessions.
- SSH public-key authentication enabled; password and keyboard-interactive authentication disabled. Prefer non-root admin with sudo; root SSH disabled only after verifying access.
- VPN individual peer keys for operator's phone/laptop and optional separate Gateway-compatible ingress peer. Never place private keys in the repo or share screenshot of QR codes.
- VPN peers allowed only the VPS management address (/32, or IPv6 /128), **not** internet tunnel routing by default. Do not configure IP forwarding/NAT unless needed.
- Outbound host default-deny remains; explicitly allow only responses to inbound WireGuard/SSH and verified operational minimum. WireGuard handshakes and established UDP replies must be tested with live UFW/nftables. The host's outbound WireGuard initiation may require special allowances for specific peers behind NAT; do not assume egress deny is transparent.
- Provider/hypervisor console + offline recovery keys remain available. Store verified backups securely.
- Auditd, fail2ban, local health report and logging cover tunnel and SSH.
- Admin GUI restricted to VPN, authenticated and MFA-protected where supported; **never publish raw TCP/51821 to the internet**.
- If using Docker-based wg-easy, inspect Docker nftables/iptables and UFW interaction; do not assume ufw alone protects Docker published ports.

## Ordered migration
1. Capture log/evidence snapshot; confirm host/IP and verified SSH host fingerprints.
2. Restore existing SSH via console. Confirm at least one remote key login **before** expanding changes.
3. While package egress is temporarily available through a controlled and logged bootstrap, install pinned WireGuard/wg-easy from trusted source. Back up config and keys with permissions 0600.
4. Set WireGuard peer IPs, DNS or IP endpoint, client configs; load on phone/laptop, and confirm live handshake, latency and SSH over VPN.
5. Establish Gateway/Tailscale route only if a supported authenticated connector can actually join the overlay; ChatGPT Work cannot be presumed to inherit the operator VPN.
6. Validate independent console recovery and fallback timer; then restrict SSH to wg interface/VPN subnet, not arbitrary source IP. Validate new session *after* restriction.
7. Then close public TCP/22 at host firewall AND provider edge firewall, verify external port closed from multiple networks, and test VPN SSH again.
8. Keep per-service rollback script, test reboot persistence, review alerting and intrusion evidence before asserting security.

## External preconditions
- Hosting provider permits inbound UDP WireGuard port.
- A stable public endpoint and knowledge of its public IPv4/IPv6.
- A managed phone/laptop with WireGuard app and secure storage of client profile.
- An independently accessible provider console or rescue method.
- Optional Gateway/Tailscale connection: requires user authorization and may be simpler than self-hosting wg-easy.
- Never use a single one-shot curl|bash installer to close TCP/22 before testing VPN ingress.

## Suggested checklist
- [ ] Snapshot/evidence collected
- [ ] VPN implementation selected: wg-easy vs native WireGuard vs Tailscale
- [ ] VPN container image pinned by immutable digest if using Docker
- [ ] Admin GUI is not publicly reachable
- [ ] Host and provider firewall permit exactly intended UDP VPN port
- [ ] Personal peer handshake verified
- [ ] SSH key login over VPN verified twice
- [ ] Gateway reachability verified independently (if needed)
- [ ] Public SSH denied
- [ ] Reboot and recovery tests passed
