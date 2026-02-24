#!/bin/bash

DOMAIN="google.com"
ALERT_DAYS=30

EXPIRY_DATE=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

EXPIRY_TS=$(date -d "$EXPIRY_DATE" +%s)
TODAY=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_TS - TODAY) / 86400 ))

echo "$DOMAIN SSL expires in $DAYS_LEFT days"
