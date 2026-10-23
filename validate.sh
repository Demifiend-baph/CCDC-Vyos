#!/bin/bash
# validate.sh - Kali-side path validation (run on KALI, not VyOS)
# Answers: is the failure routing, firewall, or application?
# Usage: validate.sh [target-ip]   (defaults: tests the standard chain)

GW=172.17.0.1            # VyOS workstation-side IP (confirm)
INTERNAL=172.16.0.254    # VyOS internal IP (confirm)
PA=172.16.0.1            # Palo Alto outside (confirm)
T=${1:-$PA}

echo "== local state =="
ip addr show | grep -E 'inet '
ip route
echo ""
echo "== hop 1: can I reach the VyOS workstation side? =="
ping -c2 $GW
echo ""
echo "== hop 2: can I reach VyOS internal side? =="
ping -c2 $INTERNAL
echo ""
echo "== hop 3: path to target $T =="
traceroute -n -m5 $T 2>/dev/null || tracepath -n -m5 $T
echo ""
echo "== hop 4: TCP + DNS + HTTP checks on $T =="
nc -vz -w3 $T 22 80 443 2>&1
dig +time=2 +tries=1 google.com 2>&1 | tail -3
curl -sI -m5 http://$T 2>&1 | head -3
echo ""
echo "Read top to bottom: first hop that fails is where the problem lives."
