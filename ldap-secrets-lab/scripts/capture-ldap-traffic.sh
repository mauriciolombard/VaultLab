#!/bin/bash
# Capture LDAP traffic for troubleshooting
# Run this on either the Vault or LDAP instance

INTERFACE=${1:-eth0}
OUTPUT_FILE=${2:-/tmp/ldap-capture-$(date +%Y%m%d-%H%M%S).pcap}
DURATION=${3:-60}

echo "=== LDAP Traffic Capture ==="
echo "Interface: $INTERFACE"
echo "Output file: $OUTPUT_FILE"
echo "Duration: $DURATION seconds"
echo ""
echo "Capturing LDAP traffic (ports 389, 636)..."
echo "Press Ctrl+C to stop early"
echo ""

sudo tcpdump -i $INTERFACE -w $OUTPUT_FILE \
    'port 389 or port 636' \
    -c 10000 &

TCPDUMP_PID=$!

sleep $DURATION
kill $TCPDUMP_PID 2>/dev/null

echo ""
echo "Capture complete: $OUTPUT_FILE"
echo ""
echo "To analyze:"
echo "  tcpdump -r $OUTPUT_FILE -A | less"
echo "  tshark -r $OUTPUT_FILE -Y ldap"
echo ""
echo "To copy to local machine:"
echo "  scp -i <key.pem> ec2-user@<ip>:$OUTPUT_FILE ."
