#!/bin/bash
# Учебный стенд warehouse-app
mkdir -p ~/warehouse/{logs/old,cache,config,bin} ~/report
for i in $(seq 1 3000); do
  printf -v ts '2026-10-%02d %02d:%02d:%02d' $((RANDOM%7+1)) $((RANDOM%24)) $((RANDOM%60)) $((RANDOM%60))
  case $((RANDOM % 20)) in
    0|1)   echo "$ts [ERROR] payment-gateway: timeout after 30s, order #$i" ;;
    2)     echo "$ts [Error] db: connection refused, order #$i" ;;
    3)     echo "$ts [error] payment-gateway: card declined, order #$i" ;;
    4|5|6) echo "$ts [WARN] stock: low quantity, item $i" ;;
    *)     echo "$ts [INFO] order-service: order #$i processed" ;;
  esac
done > ~/warehouse/logs/app.log
for n in 1 2 3; do head -c 20M /dev/zero > ~/warehouse/logs/old/app.log.$n; done
head -c 150M /dev/zero > ~/warehouse/cache/export_2026-09.tmp
touch ~/warehouse/cache/session_{01..20}.tmp
echo "port=8080" > ~/warehouse/config/app.conf
echo "host=db.local" > ~/warehouse/config/db.conf
cp "$(command -v yes)" ~/warehouse/bin/warehouse-worker
echo "Стенд готов"
