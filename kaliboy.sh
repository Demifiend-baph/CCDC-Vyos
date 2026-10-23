#!/bin/bash
# kaliboy.sh - Kali plant-detection toolkit (run on KALI)
# usage: kaliboy.sh audit | check
#
# THEORY: the Kali workstation may be a planted asset with
# persistence/callbacks. Kali's own tools are NORMAL - do not
# delete the toolset. Hunt: rogue users, keys, cron/systemd
# persistence, listeners, established outbound connections,
# SUID/world-writable surprises, /etc/hosts tampering.
#
# RULE: run 'audit' BEFORE trusting Kali as a validation
# point (validate.sh results are only as honest as this box).
# Re-run audit after any authorized change; use check between.

A=~/kali-audit
TS=$(date +%Y%m%d-%H%M%S)

snap() {
  # $1 = output directory
  mkdir -p $1
  cut -d: -f1,3,7 /etc/passwd          > $1/users.txt      # user:uid:shell
  grep -v '^#' /etc/sudoers 2>/dev/null > $1/sudoers.txt
  find /root /home -name authorized_keys 2>/dev/null -exec sh -c \
    'echo "== $1 =="; cat "$1"' _ {} \; > $1/ssh-keys.txt
  ls -la /etc/cron* 2>/dev/null         > $1/cron-files.txt
  for u in $(cut -d: -f1 /etc/passwd); do
    echo "== $u =="; crontab -l -u $u 2>/dev/null
  done > $1/crontabs.txt
  systemctl list-unit-files --state=enabled 2>/dev/null > $1/systemd-enabled.txt
  systemctl list-timers --all 2>/dev/null --no-legend   > $1/systemd-timers.txt
  ls -la /etc/systemd/system/ 2>/dev/null > $1/systemd-custom.txt
  ss -tlnp 2>/dev/null                  > $1/listeners.txt   # listening ports
  ss -tnp state established 2>/dev/null > $1/connections.txt # live outbound
  ps auxf --sort=start_time           > $1/processes.txt
  cat /etc/hosts                      > $1/hosts.txt
  cat /etc/resolv.conf                > $1/dns.txt
  find / -xdev -perm -4000 -type f 2>/dev/null | sort > $1/suid.txt
  find /tmp /var/tmp /dev/shm -type f -executable 2>/dev/null > $1/tmp-exec.txt
  tail -n 50 /root/.bash_history /home/*/.bash_history 2>/dev/null > $1/history.txt
}

case "$1" in
  audit)
    B=$A-$TS
    snap $B
    tar czf $B.tar.gz -C ~ $(basename $B)
    sha256sum $B.tar.gz | tee $B.sha256
    echo ""
    echo "audit saved: $B (+ tarball + hash)"
    echo "READ THESE FIRST: users.txt ssh-keys.txt crontabs.txt"
    echo "systemd-timers.txt listeners.txt connections.txt hosts.txt"
    echo ""
    echo "Quick eyeball - anything here needs an explanation:"
    echo "  UID 0 besides root:"; awk -F: '$2==0' $B/users.txt
    echo "  non-root shells:"; awk -F: '$3!~/nologin|false/' $B/users.txt | grep -v '^root'
    echo "  listening ports:"; awk '{print $4}' $B/listeners.txt | grep -oE '[0-9]+$' | sort -n | uniq | tr '\n' ' '; echo
    echo "  established conns:"; wc -l < $B/connections.txt
    ;;

  check)
    L=$(ls -d $A-* 2>/dev/null | tail -1)
    if [ -z "$L" ]; then
      echo "no audit found - run 'kaliboy.sh audit' first"
      exit 1
    fi
    C=/tmp/kali-check-$TS
    snap $C
    echo "--- changes since audit: $(basename $L) ---"
    for f in users.txt sudoers.txt ssh-keys.txt crontabs.txt systemd-timers.txt \
             listeners.txt connections.txt hosts.txt dns.txt suid.txt tmp-exec.txt; do
      if ! diff -q $L/$f $C/$f > /dev/null 2>&1; then
        echo "== CHANGED: $f =="
        diff $L/$f $C/$f | head -20
      fi
    done
    echo "(files not listed = unchanged)"
    ;;

  *)
    echo "usage: kaliboy.sh audit | check"
    ;;
esac
