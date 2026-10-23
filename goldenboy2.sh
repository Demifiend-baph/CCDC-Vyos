#!/bin/bash
# goldenboy2.sh - VyOS toolkit (Midwest Invitational build)
# usage: goldenboy2.sh harden|baseline|freeze|check|watch|evidence|status|revert
# sudo ONLY for revert. Everything else runs as plain vyos.
#
# EDIT ME BEFORE GAME DAY --------------------------------------------
SPLUNK=172.16.101.100        # syslog host + netflow collector IP
IF_INTERNAL=eth1             # side toward 172.16.0.254/24 (confirm name)
IF_WORKSTATION=eth2          # side toward 172.17.0.1/24 (confirm name)
# ---------------------------------------------------------------------
#
# RULES BAKED IN:
#  - harden NEVER touches firewall/NAT: ICMP stays up (ping is scored)
#  - no user renames, no IP/hostname changes (scoring depends on them)
#  - for risky MANUAL changes use: commit-confirm 5 ... then confirm
#  - revert reboots the router (~60s): ALL paths drop. Panic button only,
#    not for "I typo'd a route." Fix those surgically or via commit-confirm.
#  - re-freeze after any approved inject change, or revert undoes it.

CFG=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper
G=/config/golden.boot
H=/config/golden.sha256
TS=$(date +%Y%m%d-%H%M%S)

case "$1" in

  harden)
    $CFG begin
    ok=1
    $CFG set system syslog host $SPLUNK facility all level info || ok=0
    $CFG set system flow-accounting interface $IF_INTERNAL || ok=0
    $CFG set system flow-accounting interface $IF_WORKSTATION || ok=0
    $CFG set system flow-accounting netflow server $SPLUNK port 2055 || ok=0
    $CFG set system login banner pre-login "Authorized access only - monitored" || ok=0
    if [ $ok -eq 1 ]; then
      $CFG commit && $CFG save && echo "harden complete"
    else
      echo "SET FAILED - aborting before commit. Nothing applied."
    fi
    $CFG end
    ;;

  baseline)
    # Drop-flag step 1: capture everything BEFORE changing anything.
    # Read-only. Run after a save so config.boot is current.
    B=/config/baseline-$TS
    mkdir -p $B
    cp /config/config.boot $B/config.boot
    ip addr       > $B/interfaces.txt
    ip route      > $B/route.txt
    ip neigh      > $B/neighbors.txt
    grep -A20 'firewall' /config/config.boot > $B/firewall.txt 2>/dev/null
    grep -A20 'nat'      /config/config.boot > $B/nat.txt 2>/dev/null
    sha256sum $B/config.boot | awk '{print $1}' > $B/SHA256
    echo "baseline saved: $B"
    cat $B/SHA256
    echo "copy this directory off the box."
    ;;

  freeze)
    cp /config/config.boot $G && echo "golden frozen"
    sha256sum $G | awk '{print $1}' > $H
    echo "hash: $(cat $H)  <-- record off-box"
    ;;

  check)
    echo "--- config changes since last freeze ---"
    diff $G /config/config.boot && echo "no changes"
    echo ""
    echo "--- route changes since last watch ---"
    if [ -f /config/route.last ]; then
      ip route > /tmp/route.now
      diff /config/route.last /tmp/route.now && echo "no route changes"
    else
      echo "run 'watch' once first to establish route baseline"
    fi
    ;;

  watch)
    # Route drift detector. Run by hand, or schedule via task-scheduler
    # every 15 min. Unexpected static/default routes = top persistence
    # indicator. Read-only, safe to run constantly.
    ip route > /tmp/route.now
    if [ -f /config/route.last ]; then
      if ! diff -q /config/route.last /tmp/route.now > /dev/null; then
        echo "=== ROUTE CHANGE at $(date) ===" >> /config/route-watch.log
        diff /config/route.last /tmp/route.now >> /config/route-watch.log
        echo "--" >> /config/route-watch.log
        echo "ALERT: route table changed - see /config/route-watch.log"
      else
        echo "routes unchanged"
      fi
    else
      echo "first run: route baseline established"
    fi
    cp /tmp/route.now /config/route.last
    ;;

  evidence)
    # IR bundle: capture before you remediate. Hash it. Copy off-box.
    E=/config/evidence-$TS.tar.gz
    tar czf $E /config/config.boot /config/golden.boot \
               /config/route-watch.log /var/log/syslog 2>/dev/null
    sha256sum $E
    echo "evidence bundle: $E  <-- copy off-box"
    ;;

  status)
    echo "live:     $(sha256sum /config/config.boot | awk '{print $1}')"
    echo "golden:   $(sha256sum $G | awk '{print $1}')"
    echo "recorded: $(cat $H)"
    ;;

  revert)
    if [ "$(id -u)" -ne 0 ]; then
      echo "needs sudo: sudo goldenboy2.sh revert"
      exit 1
    fi
    if [ "$(sha256sum $G | awk '{print $1}')" = "$(cat $H)" ]; then
      cp $G /config/config.boot && reboot
    else
      echo "HASH MISMATCH - do not revert. Use GRUB image fallback."
    fi
    ;;

  *)
    echo "usage: goldenboy2.sh harden|baseline|freeze|check|watch|evidence|status|revert"
    echo "       (sudo only for revert)"
    ;;
esac
