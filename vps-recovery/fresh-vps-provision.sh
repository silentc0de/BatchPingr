#!/usr/bin/env bash
# Ubuntu 24.04/26.04 console-first staged VPS provisioning. Run on a FRESH TRUSTED VPS.
set -Eeuo pipefail
umask 077
export DEBIAN_FRONTEND=noninteractive
BASE=/root/vps-bootstrap
LOGDIR=/var/log/vps-bootstrap
mkdir -p "$BASE" "$LOGDIR"; chmod 700 "$BASE" "$LOGDIR"
LOG="$LOGDIR/$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "FAIL: unexpected error at line $LINENO (exit $?)" >&2' ERR
[[ $EUID == 0 ]] || { echo "Must run as root in provider console" >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu ]] || { echo "Ubuntu required" >&2; exit 1; }
PAUSE_SECS=3
SUMMARY="$LOGDIR/summary.txt"
: > "$SUMMARY"; chmod 600 "$SUMMARY"
good(){ echo "PASS: $1" | tee -a "$SUMMARY"; }
warn(){ echo "WARNING: $1" | tee -a "$SUMMARY"; }
bad(){ echo "FAIL: $1" | tee -a "$SUMMARY"; }
step(){
  local label="$1" rc=0; shift
  echo; echo "======== $label ========"
  "$@" || rc=$?
  if ((rc == 0)); then good "$label"; else bad "$label (exit $rc); inspect $LOG"; fi
  sleep "$PAUSE_SECS"
  return 0
}
backup(){ [[ ! -e "$1" ]] || cp -a "$1" "$BASE/$(basename "$1").$(date -u +%s).bak"; }
evidence(){
  echo '=== Pre-change evidence ==='
  date -u; uptime; ip -br address || true
  last -F -n 30 || true
  journalctl -u ssh -n 150 --no-pager || true
  ss -lntup || true
  for user in root kenneth; do
    f="/home/$user/.ssh/authorized_keys"
    [[ "$user" == root ]] && f=/root/.ssh/authorized_keys
    if [[ -f "$f" ]]; then ssh-keygen -lf "$f" || true; fi
  done
  backup /etc/ssh/sshd_config
  backup /etc/ufw/user.rules
  backup /etc/ufw/user6.rules
}
keys(){
  local key="$BASE/vps-initial-access"
  if [[ ! -e "$key" ]]; then
    ssh-keygen -q -t ed25519 -a 100 -N '' -C "vps-initial-access-$(date -u +%Y%m%d)" -f "$key" || return
  fi
  install -d -m 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  local pub
  pub="$(cat "$key.pub")"
  grep -Fxq -- "$pub" /root/.ssh/authorized_keys || printf '%s\n' "$pub" >> /root/.ssh/authorized_keys
  ssh-keygen -lf "$key.pub"
  echo 'WARNING: key is currently stored UNENCRYPTED locally until encrypted handoff. Do not delete until delivery succeeds.'
}
early_firewall(){
  # Never activate until ssh listener and existing authorized key have been checked.
  # If UFW is absent, install that one trusted package while guest egress is still available.
  if ! command -v ufw >/dev/null; then
    timeout 180 apt-get -o DPkg::Lock::Timeout=30 update || return 1
    timeout 180 apt-get -o DPkg::Lock::Timeout=30 install -y ufw || return 1
  fi
  command -v sshd >/dev/null || { echo 'FAIL-SAFE: sshd missing'; return 1; }
  sshd -t || return 1
  systemctl is-active --quiet ssh || { echo 'FAIL-SAFE: SSH not active'; return 1; }
  ss -lnt | grep -Eq ':22[[:space:]]' || { echo 'FAIL-SAFE: port 22 absent'; return 1; }
  [[ -s /root/.ssh/authorized_keys ]] || { echo 'FAIL-SAFE: no authorized SSH key'; return 1; }
  for p in /etc/ufw/user.rules /etc/ufw/user6.rules; do backup "$p"; done
  # Narrow initial exposure: only existing SSH inbound and temporary provisioning traffic outbound.
  # These outbound exceptions are intentional and temporary, but are NOT destination-pinned.
  ufw allow 22/tcp comment 'TEMP SSH before verified key-only/VPN'
  ufw default deny incoming
  ufw default deny outgoing
  ufw default deny routed
  ufw allow out 53/udp comment 'TEMP provisioning DNS'
  ufw allow out 53/tcp comment 'TEMP provisioning DNS TCP'
  ufw allow out 80/tcp comment 'TEMP Ubuntu HTTP repositories'
  ufw allow out 443/tcp comment 'TEMP HTTPS provisioning'
  ufw logging on
  ufw --force enable
  ufw status verbose
  [[ "$(ufw status | head -1)" == 'Status: active' ]]
}
close_bootstrap_egress(){
  # Remove the temporary broad outbound permissions even if later provisioning stages failed.
  command -v ufw >/dev/null || return 1
  ufw --force delete allow out 53/udp || true
  ufw --force delete allow out 53/tcp || true
  ufw --force delete allow out 80/tcp || true
  ufw --force delete allow out 443/tcp || true
  ufw default deny outgoing || return 1
  ufw status verbose
}
bootstrap_packages(){
  timeout 180 apt-get -o DPkg::Lock::Timeout=30 update || return
  timeout 600 apt-get -o DPkg::Lock::Timeout=30 install -y openssh-server openssh-client ufw fail2ban nftables auditd audispd-plugins apparmor apparmor-utils unattended-upgrades aide python3-cryptography ca-certificates curl jq || return
}
delivery(){
  local key="$BASE/vps-initial-access" bundle="$BASE/vps-ssh-keys.tar.gz" enc="$BASE/vps-ssh-keys.enc"
  [[ -s "$key" && -s "$key.pub" ]] || return 1
  tar -C "$BASE" -czf "$bundle" vps-initial-access vps-initial-access.pub
  # Authenticated AES-256-GCM encrypted outer package, password displayed ONLY on console.
  local pass
  pass="$(openssl rand -hex 24)" || return
  python3 - "$bundle" "$enc" "$pass" <<'PY'
import json,os,sys,base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
raw=open(sys.argv[1],'rb').read()
salt=os.urandom(16); nonce=os.urandom(12)
k=Scrypt(salt=salt,length=32,n=2**15,r=8,p=1).derive(sys.argv[3].encode())
cipher=AESGCM(k).encrypt(nonce,raw,b'vps-bootstrap-v1')
d={'format':'vps-bootstrap-v1','salt':base64.b64encode(salt).decode(),'nonce':base64.b64encode(nonce).decode(),'ciphertext':base64.b64encode(cipher).decode()}
fd=os.open(sys.argv[2],os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f: json.dump(d,f)
PY
  rm -f "$bundle"
  if ! command -v ffsend >/dev/null 2>&1 && command -v snap >/dev/null 2>&1; then
    echo 'ffsend absent; attempting the upstream-recommended snap package before outbound lockdown.'
    timeout 240 snap install ffsend || true
  fi
  if ! command -v ffsend >/dev/null 2>&1; then
    warn 'ffsend not available. Encrypted bundle retained locally; handoff and SSH password-lock gate deferred.'
    return 3
  fi
  local output link
  output="$(ffsend upload --downloads 1 --expiry-time 1h "$enc" 2>&1)" || { warn "Upload failed: $output"; return 4; }
  link="$(printf '%s\n' "$output" | grep -Eo 'https://send\.vis\.ee/[^[:space:]]+' | head -1)"
  [[ -n "$link" ]] || { warn 'No Send link detected in output'; return 5; }
  printf '%s\n' "$link" > "$BASE/delivery-link.txt"
  chmod 600 "$BASE/delivery-link.txt"
  echo "ONE-DOWNLOAD URL: $link"
  printf '%s\n' "SEPARATE DECRYPTION SECRET (SAVE OFFLINE; NEVER POST ON EDUTHO): $pass" >/dev/tty
  echo 'Only the encrypted outer package is uploaded. Save the secret separately. The secret is NOT written to the installer log.'
  # Keep private key local until a verified external login; do not prematurely delete.
}
ssh_service(){
  sshd -t && systemctl enable --now ssh && systemctl is-active --quiet ssh || return 1
  echo 'SERVER HOST FINGERPRINT (compare out of band when connecting):'
  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub || true
}
gate(){
  echo
  echo 'MANDATORY: download the one-use package to YOUR device, save the separate secret, decrypt, and verify a real SSH key login from another device.'
  echo 'Do NOT enter the gate phrase until a fresh key-based session works and host fingerprint is verified independently.'
  read -r -p 'Type VERIFIED-KEY-LOGIN to turn off SSH passwords, or press ENTER to defer: ' reply
  [[ -f "$BASE/delivery-link.txt" ]] || { warn 'No confirmed ffsend handoff link exists. Password lockdown deferred.'; return 3; }
  [[ "$reply" == VERIFIED-KEY-LOGIN ]] || { warn 'Key login not verified; keeping current SSH auth. Further tools continue.'; return 3; }
  printf 'verified\n' > "$BASE/verified-key-login"; chmod 600 "$BASE/verified-key-login"
}
ssh_lock(){
  [[ -s "$BASE/verified-key-login" ]] || return 3
  mkdir -p /etc/ssh/sshd_config.d
  backup /etc/ssh/sshd_config.d/00-vps-key-only.conf
  cat > /etc/ssh/sshd_config.d/00-vps-key-only.conf <<'CONF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PermitEmptyPasswords no
CONF
  sshd -t && systemctl reload ssh || return
  sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin) '
  [[ "$(sshd -T | awk '$1=="passwordauthentication"{print $2}')" == no ]] || return 1
  [[ "$(sshd -T | awk '$1=="kbdinteractiveauthentication"{print $2}')" == no ]] || return 1
  rm -f "$BASE/vps-initial-access"
  echo 'Local private key deleted after verified external login; encrypted backup retained locally.'
}
fail2ban(){
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/99-vps-ssh.conf <<'CONF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
CONF
  fail2ban-client -t && systemctl enable --now fail2ban &&
  systemctl restart fail2ban && fail2ban-client status sshd
}
auditing(){
  mkdir -p /var/log/journal /etc/audit/rules.d
  systemd-tmpfiles --create --prefix /var/log/journal
  cat > /etc/audit/rules.d/99-vps-critical.rules <<'RULES'
-w /etc/passwd -p wa -k vps-users
-w /etc/group -p wa -k vps-users
-w /etc/shadow -p wa -k vps-credentials
-w /etc/sudoers -p wa -k vps-sudo
-w /etc/ssh/sshd_config -p wa -k vps-ssh
RULES
  systemctl enable --now auditd && augenrules --load && systemctl is-active --quiet auditd
}
updates(){
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
  echo 'Unattended-Upgrade::Automatic-Reboot "false";' >/etc/apt/apt.conf.d/90-vps-no-reboot
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
  echo 'NOTE: after outgoing default deny, automatic downloads are blocked. Maintenance windows must allow updates.'
}
apparmor_check(){ aa-status; }
aide_setup(){
  echo 'AIDE installed. DO NOT call its baseline clean until forensic verification.'
  command -v aide && echo 'Run and review aideinit separately after verifying server trust.'
}
optional_observers(){
  if apt-cache show crowdsec >/dev/null 2>&1; then
    timeout 240 apt-get -o DPkg::Lock::Timeout=30 install -y crowdsec || return 3
    systemctl enable --now crowdsec || return 3
    echo 'CrowdSec detection engine installed; bouncer NOT activated, no ban enforcement claimed.'
  else
    warn 'CrowdSec unavailable in configured repositories; cannot install trusted package automatically.'
  fi
  echo 'OpenSnitch GUI approval deferred until authenticated remote interface exists; UFW outbound deny will enforce isolation.'
  echo 'AEGIS deferred: verified artifact/source not available, do not substitute an unknown program.'
  echo 'Cloudflare Access, VPN and provider firewall are external integration tasks.'
}
sandbox_template(){
  install -d -m 700 /root/vps-hardening-examples
  cat >/root/vps-hardening-examples/app-override.conf <<'HARDEN'
[Service]
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
# Specify application-specific ReadWritePaths before applying.
HARDEN
  chmod 600 /root/vps-hardening-examples/app-override.conf
}
local_monitor(){
  cat >/usr/local/sbin/vps-health <<'HEALTH'
#!/usr/bin/env bash
umask 077
{ date -u; for x in ssh fail2ban auditd; do echo "$x: $(systemctl is-active "$x" 2>/dev/null)"; done; ss -lntup; ufw status verbose; df -h /; } >/var/log/vps-bootstrap/health-last.txt
HEALTH
  chmod 700 /usr/local/sbin/vps-health
  cat >/etc/systemd/system/vps-health.service <<'SERVICE'
[Unit]
Description=Local VPS security health report
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vps-health
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/log/vps-bootstrap
PrivateTmp=yes
SERVICE
  cat >/etc/systemd/system/vps-health.timer <<'TIMER'
[Unit]
Description=Local VPS security health timer
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
[Install]
WantedBy=timers.target
TIMER
  systemctl daemon-reload
  systemctl enable --now vps-health.timer
  systemctl start vps-health.service
  test -s "$LOGDIR/health-last.txt"
}
firewall(){
  command -v ufw && systemctl is-active --quiet ssh || { echo 'Cannot safely apply firewall: ssh inactive'; return 1; }
  ss -lnt | grep -Eq ':22[[:space:]]' || { echo 'Cannot safely apply firewall: port 22 absent'; return 1; }
  if [[ -s "$BASE/verified-key-login" ]] &&
     [[ "$(sshd -T | awk '$1=="passwordauthentication"{print $2}')" == no ]] &&
     [[ "$(sshd -T | awk '$1=="kbdinteractiveauthentication"{print $2}')" == no ]]; then
    ufw allow 22/tcp comment 'TEMPORARY key-only SSH until VPN verified' || return 1
    echo 'Verified key-only SSH: temporary TCP 22 access permitted.'
  else
    echo 'SECURITY FAIL-SAFE: no verified key-only login. Closing inbound port 22; use provider console until secure handoff is complete.'
    ufw --force delete allow 22/tcp || true
  fi
  ufw default deny incoming && ufw default deny outgoing &&
  ufw logging on && ufw --force enable && ufw status verbose
}
status(){
  echo 'FINAL STATUS'; systemctl is-active ssh fail2ban auditd || true
  sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin)' || true
  ufw status verbose || true
  echo 'PENDING: external provider edge rules, OpenSnitch remote GUI, verified AEGIS, CrowdSec vetted bouncer, cloud MFA, VPN-only SSH, separate admin.'
}
step 'Generate Ed25519 key and authorize public key for root' keys
step 'Capture initial security evidence before installing tools' evidence
step 'EARLY UFW: deny incoming/outgoing; temporary restricted-port provisioning egress' early_firewall
if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
  echo 'CRITICAL: firewall could not be enabled. Abort before downloading/installing additional tools.'
  exit 1
fi
step 'Install trusted Ubuntu security dependencies' bootstrap_packages
step 'Upload encrypted one-use key handoff if ffsend is available' delivery
step 'Start and validate SSH daemon' ssh_service
step 'Manual verified-key-login checkpoint' gate
step 'Disable SSH passwords (only after VERIFIED gate)' ssh_lock
step 'Install/configure/test Fail2Ban sshd jail' fail2ban
step 'Configure auditd and persistent journal' auditing
step 'Enable unattended upgrades (blocked after final outbound deny)' updates
step 'Check AppArmor' apparmor_check
step 'CrowdSec detection and external integration checks' optional_observers
step 'Create app-specific systemd sandbox template' sandbox_template
step 'Install AIDE; defer baseline trust assessment' aide_setup
step 'Enable local 5-minute monitoring' local_monitor
step 'Close all temporary bootstrap outbound allowances' close_bootstrap_egress
step 'Final UFW deny inbound/outbound; permit SSH only if key-only login verified' firewall
step 'Final checks' status
echo "SUMMARY: $(cat "$SUMMARY" | tail -n 30)"
echo "Saved logs: $LOG ; $SUMMARY"
echo 'ACTION REQUIRED: no outbound until approved maintenance window. Public SSH remains temporarily allowed until VPN works.'
