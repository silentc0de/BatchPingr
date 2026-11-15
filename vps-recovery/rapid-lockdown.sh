#!/usr/bin/env bash
# Serial console wrapper for pinned recovery actions.
set -uo pipefail
umask 077
[[ $(id -u) == 0 ]] || { echo 'FAIL: run as root'; exit 1; }
D=/var/log/vps-recovery
mkdir -p "$D"; chmod 700 "$D"
L="$D/rapid-$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$L") 2>&1
SCRIPT=/root/recover-vps.sh
URL=https://raw.githubusercontent.com/silentc0de/BatchPingr/15c5c274250f848193809ba59a9fefdf0b3d8e16/vps-recovery/recover-vps.sh
pass=0; warn=0
stage(){
 local name="$1" rc=0
 shift
 echo; echo "==== $name ===="
 "$@" || rc=$?
 if ((rc==0)); then echo "PASS: $name"; ((pass+=1))
 else echo "WARNING/FAIL: $name exit=$rc; continuing, review $L"; ((warn+=1)); fi
 sleep 3
}
fetch(){
 curl -fL --connect-timeout 15 --max-time 90 "$URL" -o "$SCRIPT" && bash -n "$SCRIPT"
}
stage 'Download pinned recovery helper and syntax-check' fetch
if [[ ! -s "$SCRIPT" ]]; then echo 'FAIL: helper download not available'; exit 1; fi
stage 'Preserve pre-change evidence' bash "$SCRIPT" audit
if [[ "${1:-}" == --audit-only ]]; then echo "Log: $L"; exit 0; fi
stage 'Install auditd, AppArmor, updates, local monitor (before egress deny)' bash "$SCRIPT" security-prep
stage 'Write conservative application systemd hardening template' bash "$SCRIPT" systemd-template
if apt-cache show crowdsec >/dev/null 2>&1; then
  stage 'CrowdSec local detection engine (bouncer remains pending)' bash "$SCRIPT" install-crowdsec
else echo 'WARNING: CrowdSec absent from configured repositories; skipped'; ((warn+=1)); fi
echo 'WARNING: OpenSnitch remote GUI approval deferred until authenticated access'; ((warn+=1))
stage 'Recover SSH, install Fail2Ban, apply UFW deny incoming and outgoing' bash "$SCRIPT" recover
stage 'Final SSH, audit, firewall and monitoring status' bash "$SCRIPT" security-status
echo; echo "SUMMARY PASS=$pass WARN=$warn"
echo "Logs: $L and /var/log/vps-recovery/"
echo 'Pending: SSH verification, root SSH disable, VPN, provider firewall, CrowdSec bouncer, OpenSnitch GUI, AEGIS, Cloudflare Access, off-host logging.'
echo 'Keep provider console available until remote SSH works.'
