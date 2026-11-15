#!/usr/bin/env bash
# Console-first Ubuntu SSH recovery. Blocks NEW outbound connections after package bootstrap.
set -Eeuo pipefail
umask 077
[ "$(id -u)" = 0 ] || { echo 'Run as root in the provider console'; exit 1; }
. /etc/os-release
[ "$ID" = ubuntu ] || { echo 'Ubuntu required'; exit 1; }
mode="$1"
mkdir -p /var/log/vps-recovery
chmod 700 /var/log/vps-recovery
log="/var/log/vps-recovery/$(date -u +%Y%m%d-%H%M%S)-$mode.log"
exec > >(tee -a "$log") 2>&1
report() {
 echo '=== Timestamp, boot, network and listeners ==='
 date -u; uptime; ip -br address; ss -tlnp
 echo '=== Logins and SSH events ==='
 last -F -n 25 || true
 journalctl -u ssh --no-pager -n 120 || true
 echo '=== Users, keys and firewall ==='
 getent passwd | awk -F: '($3==0 || $3>=1000) {print $1,$3,$7}'
 for f in /root/.ssh/authorized_keys /home/kenneth/.ssh/authorized_keys; do
   if [ -f "$f" ]; then echo "$f"; ssh-keygen -lf "$f" || true; fi
 done
 ufw status verbose || true
 if command -v sshd >/dev/null; then sshd -T | grep -Ei '^(port|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication) ' || true; fi
}
case "$mode" in
 audit) report ;;
 recover)
   report
   cp -a /etc/ssh/sshd_config "/var/log/vps-recovery/sshd-config-$(date -u +%s).bak"
   apt-get update
   DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server ufw fail2ban python3-systemd
   sshd -t
   systemctl unmask ssh || true
   systemctl enable --now ssh
   ss -tlnp | grep -E ':22[[:space:]]' || { echo 'SSH NOT LISTENING ON 22: inspect service'; exit 1; }
   ufw allow 22/tcp comment 'SSH recovery'
   ufw default deny incoming
   # Default egress DENY: no new internet-bound connections initiated by this VPS.
   # Stateful replies to inbound SSH are normally allowed by UFW's established rules.
   ufw default deny outgoing
   ufw logging on
   ufw --force enable
   ufw status verbose
   echo '=== Configure Fail2Ban SSH jail ==='
   mkdir -p /etc/fail2ban/jail.d
   cat > /etc/fail2ban/jail.d/99-vps-ssh.conf <<'JAIL'
[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
   fail2ban-client -t
   systemctl enable --now fail2ban
   fail2ban-client status sshd
   echo 'Outbound policy is DENY. APT, DNS queries, updates and alerts cannot initiate traffic unless separately approved.'
   echo 'Now test remote SSH key login. DO NOT run lock-ssh before success.' ;;
 lock-ssh)
   [ -s /root/.ssh/authorized_keys ] || [ -s /home/kenneth/.ssh/authorized_keys ] || { echo 'No expected keys found'; exit 1; }
   read -r -p 'After verified remote key login, type VERIFIED-KEY-LOGIN: ' answer
   [ "$answer" = VERIFIED-KEY-LOGIN ] || exit 1
   mkdir -p /etc/ssh/sshd_config.d
   cat > /etc/ssh/sshd_config.d/99-vps-key-only.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
CONF
   sshd -t
   systemctl reload ssh
   sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '
   echo 'Test a SECOND SSH key login before closing the current one.' ;;
 install-opensnitch)
   if ! apt-cache show opensnitch >/dev/null 2>&1; then
      echo 'Not in configured apt sources; review https://github.com/evilsocket/opensnitch/releases (no unverified downloads).'; exit 3
   fi
   echo 'WARNING: Outbound firewall deny will block downloads. This mode will not open outbound access.'
   DEBIAN_FRONTEND=noninteractive apt-get install -y --no-download opensnitch
   cfg=/etc/opensnitchd/default-config.json
   [ -f "$cfg" ] || { echo 'Daemon config missing'; exit 1; }
   cp -a "$cfg" "/var/log/vps-recovery/opensnitch-$(date -u +%s).bak"
   python3 - "$cfg" <<'PY'
import json,sys,os,tempfile
p=sys.argv[1]
with open(p) as f: c=json.load(f)
c['DefaultAction']='allow'
fd,t=tempfile.mkstemp(dir=os.path.dirname(p))
with os.fdopen(fd,'w') as f: json.dump(c,f,indent=2)
os.chmod(t,0o600);os.replace(t,p)
PY
   systemctl enable --now opensnitch
   echo 'Observation mode only. Remote authenticated GUI required for approval prompts.' ;;
 deny-egress)
   echo 'REFUSED: headless default-deny without authenticated connected GUI and rollback would cause lockout.'; exit 4 ;;

 security-prep)
   # Must precede 'recover', because 'recover' intentionally closes outbound traffic.
   echo '=== Install monitoring and audit packages BEFORE outbound lockdown ==='
   apt-get update
   DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins unattended-upgrades needrestart apparmor apparmor-utils jq
   systemctl enable --now auditd
   mkdir -p /etc/audit/rules.d
   cat > /etc/audit/rules.d/99-vps-identity.rules <<'AUDIT'
-w /etc/passwd -p wa -k vps-identity
-w /etc/group -p wa -k vps-identity
-w /etc/shadow -p wa -k vps-credentials
-w /etc/sudoers -p wa -k vps-sudo
-w /etc/sudoers.d/ -p wa -k vps-sudo
-w /etc/ssh/sshd_config -p wa -k vps-ssh
-w /etc/ssh/sshd_config.d/ -p wa -k vps-ssh
AUDIT
   augenrules --load
   echo '=== Persistent journal ==='
   mkdir -p /var/log/journal
   systemd-tmpfiles --create --prefix /var/log/journal
   systemctl restart systemd-journald
   echo '=== Automatic security updates, no automatic reboot ==='
   cat > /etc/apt/apt.conf.d/20auto-upgrades <<'UPDATES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
UPDATES
   cat > /etc/apt/apt.conf.d/90-vps-no-autoreboot <<'UPDATES'
Unattended-Upgrade::Automatic-Reboot "false";
UPDATES
   systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
   echo 'Note: after outbound default-deny, unattended-upgrades will NOT be able to fetch updates. Approved update windows are necessary.'
   echo '=== Local-only health monitoring ==='
   cat > /usr/local/sbin/vps-security-health <<'HEALTH'
#!/usr/bin/env bash
set -u
f=/var/log/vps-recovery/health-last.txt
{
  date -u
  echo '=== Firewall ==='
  ufw status verbose || true
  echo '=== Security services ==='
  for s in ssh fail2ban auditd apparmor; do systemctl is-active "$s" || true; done
  echo '=== Socket listeners ==='
  ss -tlnp || true
  echo '=== Disk ==='
  df -h / /var/log || true
  echo '=== Updates pending ==='
  test ! -f /var/run/reboot-required || echo 'REBOOT REQUIRED'
} > "$f"
chmod 600 "$f"
HEALTH
   chmod 700 /usr/local/sbin/vps-security-health
   cat > /etc/systemd/system/vps-security-health.service <<'SERVICE'
[Unit]
Description=Local VPS security status report
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vps-security-health
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/log/vps-recovery
ProtectHome=true
PrivateTmp=true
SERVICE
   cat > /etc/systemd/system/vps-security-health.timer <<'TIMER'
[Unit]
Description=Periodic local VPS security status
[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
Persistent=true
[Install]
WantedBy=timers.target
TIMER
   systemctl daemon-reload
   systemctl enable --now vps-security-health.timer
   echo 'Health report: /var/log/vps-recovery/health-last.txt'
   echo 'Audit query: ausearch -k vps-ssh; for commands see audit coverage caveats in README.'
   ;;
 install-crowdsec)
   # Local engine only. Firewall bouncer requires confirmed backend and rule integration.
   # Restrictive egress may prevent repository use or external reputation feeds.
   if ! apt-cache show crowdsec >/dev/null 2>&1; then
     echo 'CrowdSec not available in configured trusted apt repos. Refusing unverified curl|sh.'
     exit 3
   fi
   DEBIAN_FRONTEND=noninteractive apt-get install -y --no-download crowdsec
   systemctl enable --now crowdsec
   cscli version || true
   echo 'CrowdSec engine installed. No bouncer installed, NO automatic block enforcement yet.'
   echo 'For blocking, manually verify compatible nftables/iptables backend and bouncer package.'
   echo 'CrowdSec global reputation lists need approved outbound traffic.'
   ;;
 restrict-ssh)
   echo 'Restrict SSH source only after a verified key connection and a tested console recovery route.'
   echo 'This command adds an ALLOW for a specified /32 (IPv4) or /128 (IPv6), then removes the broad port rule.'
   read -r -p 'Trusted administrative public IP (numeric IPv4 only): ' admin_ip
   if ! python3 - "$admin_ip" <<'PY'
import ipaddress,sys
x=ipaddress.ip_address(sys.argv[1])
assert x.version==4 and x.is_global
PY
   then echo 'Invalid/non-global IPv4 address'; exit 1; fi
   read -r -p 'Type VERIFIED-KEY-AND-CONSOLE to enforce source restriction: ' confirmation
   [ "$confirmation" = VERIFIED-KEY-AND-CONSOLE ] || exit 1
   ufw allow from "$admin_ip" to any port 22 proto tcp comment 'trusted-admin-ssh'
   ufw --force delete allow 22/tcp || true
   ufw status numbered
   echo 'Verify from that address immediately. Dynamic/mobile IPs may change.'
   ;;
 systemd-template)
   echo 'Creating EXAMPLE hardening drop-in only; NOT applying to SSH, Docker, or running app services.'
   mkdir -p /root/vps-hardening-examples
   cat > /root/vps-hardening-examples/app-override.conf <<'HARDEN'
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
# Customize ReadWritePaths and service credentials BEFORE deploying to an app.
# ReadWritePaths=/var/lib/your-app
HARDEN
   chmod 600 /root/vps-hardening-examples/app-override.conf
   echo 'Example created: /root/vps-hardening-examples/app-override.conf'
   ;;
 security-status)
   echo '=== Nine-layer hardening status ==='
   echo '[1] CrowdSec'; command -v cscli && cscli version || true
   echo '[2] Layered firewalls'; ufw status verbose || true; echo 'Provider edge firewall must be checked in hosting account.'
   echo '[3] SSH source restriction'; ufw status numbered || true
   echo '[4] Cloudflare Access'; echo 'External setup required. Not installed.'
   echo '[5] SSH key-only'; sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin) ' || true
   echo '[6] systemd sandbox'; echo 'Per-service deployment required'; systemd-analyze security ssh.service 2>/dev/null | tail -n 3 || true
   echo '[7] auditd'; systemctl is-active auditd || true
   echo '[8] unattended upgrades'; systemctl is-enabled apt-daily-upgrade.timer || true
   echo '[9] 24/7 monitoring'; systemctl is-enabled vps-security-health.timer || true
   echo 'External HAL/Titus/Dependabot integrations require separate verified accounts and project configuration.'
   echo '=== Egress policy ==='; ufw status verbose || true
   ;;
 *) echo 'Usage: bash recover-vps.sh audit|security-prep|recover|lock-ssh|install-opensnitch|install-crowdsec|restrict-ssh|systemd-template|security-status|deny-egress'; exit 2 ;;
esac
