#!/bin/bash
set -euo pipefail

#luu y file config.txt o cung cap thu muc voi file.sh
CRED_FILE="config.txt"

# check file config.txt
if [ ! -r "$CRED_FILE" ]; then
  echo "Khong tim thay hoac khong the doc duoc file: $CRED_FILE" >&2
  exit 1
fi
#doc file, loai bo comment va dong trong thua
lines=()
while IFS= read -r rawline; do
  #Lam sach khoang trang 2 dau
  line="$(printf '%s' "$rawline" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  #Loai bo dong trong va comment
  if [ -z "$line" ] || [[ "$line" == \#* ]]; then
    continue
  fi
  lines+=("$line")
done < "$CRED_FILE"

HOST_USER="${lines[0]:-}"
HOST_PASS="${lines[1]:-}"
RASPI_USER="${lines[2]:-}"
RASPI_PASS="${lines[3]:-}"
RASPI_IP="${lines[4]:-}"

    
PKGS="$(tr '\n' ' ' < dep_list_raspi.txt)"
sshpass -p "$RASPI_PASS" ssh -t -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "printf '%s\n' \"$RASPI_PASS\" | sudo -S -p '' apt install -y $PKGS"
  
sshpass -p "$RASPI_PASS" ssh -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "printf '%s\n' '$RASPI_PASS' | sudo -S mkdir -p /usr/local/qt6 && \
  printf '%s\n' '$RASPI_PASS' | sudo -S chmod 777 /usr/local/bin"

  
sshpass -p "$RASPI_PASS" ssh -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "echo 'export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/qt6/lib/' >> ~/.bashrc && source ~/.bashrc"

