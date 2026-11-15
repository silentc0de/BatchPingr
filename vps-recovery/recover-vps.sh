#!/usr/bin/env bash
# Console-first Ubuntu SSH recovery. Never blocks outbound traffic automatically.
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
   DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server ufw
   sshd -t
   systemctl unmask ssh || true
   systemctl enable --now ssh
   ss -tlnp | grep -E ':22[[:space:]]' || { echo 'SSH NOT LISTENING ON 22: inspect service'; exit 1; }
   ufw allow 22/tcp comment 'SSH recovery'
   ufw default deny incoming
   ufw default allow outgoing
   ufw --force enable
   ufw status verbose
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
   apt-get update
   if ! apt-cache show opensnitch >/dev/null 2>&1; then
      echo 'Not in configured apt sources; review https://github.com/evilsocket/opensnitch/releases (no unverified downloads).'; exit 3
   fi
   DEBIAN_FRONTEND=noninteractive apt-get install -y opensnitch
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
 *) echo 'Usage: bash recover-vps.sh audit|recover|lock-ssh|install-opensnitch|deny-egress'; exit 2 ;;
esac
