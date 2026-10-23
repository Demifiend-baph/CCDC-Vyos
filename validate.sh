#!/bin/bash
# validate.sh - Kali-side path validation (run on KALI, not VyOS)
# Answers: is the failure routing, firewall, or application?
# Usage: validate.sh [target-ip]   (default target: Palo Alto outside)

GW=172.17.0.1              # VyOS workstation side (Kali's gateway)
INTERNAL=172.16.0.254      # VyOS internal/transit side
PA=172.16.0.1              # Palo Alto outside interface
LAN_SPLUNK=172.20.240.20   # a LAN destination to prove the full path
T=${1:-$PA}

echo "== local state =="
ip addr show | grep -E 'inet '
ip route
echo ""
echo "== hop 1: VyOS workstation side ($GW) =="
ping -c2 $GW
echo ""
echo "== hop 2: VyOS internal side ($INTERNAL) =="
ping -c2 $INTERNAL
echo ""
echo "== hop 3: path to target $T =="
traceroute -n -m5 $T 2>/dev/null || tracepath -n -m5 $T
echo ""
echo "== hop 4: LAN reachability (through PA) + TCP/DNS/HTTP =="
ping -c2 $LAN_SPLUNK
nc -vz -w3 $T 22 443 2>&1
dig +time=2 +tries1 ccdc.events 2>&1 | tail -3
curl -sI -m5 http://$T 2>&1 | head -3
echo ""
echo "First hop that fails = where the problem lives."
echo "VyOS good but LAN dead? Coordinate with Sam (Palo Alto),"
echo "or check that the target service itself is up."
