#!/bin/bash
# Generate a random MAC address and check for collisions on the local network

# Generate MAC address (using Microsoft Hyper-V OUI for WSL2)
hexchars="0123456789ABCDEF"

while true; do
  mac="00:15:5D"
  for i in {1..3}; do
    mac+=:$(echo $hexchars | fold -w2 | shuf | head -n1)
  done
  echo "Generated MAC: $mac"
  arp -a | awk '{print $4}' | grep -i "$mac" > /dev/null
  if [ $? -eq 0 ]; then
    echo "Collision detected: $mac is already in use on the network! Regenerating..."
  else
    echo "No collision detected. $mac is safe to use."
    break
  fi
done
