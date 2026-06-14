#!/usr/bin/env bash
set -euo pipefail

PROJECT="retail-project-499413"
LOCATION="US"

bq --location="$LOCATION" mk -d --description "Raw ingested layer" "${PROJECT}:retail_bronze"
bq --location="$LOCATION" mk -d --description "Cleaned layer" "${PROJECT}:retail_silver"
bq --location="$LOCATION" mk -d --description "Analytics layer" "${PROJECT}:retail_gold"

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace \
  "${PROJECT}:retail_bronze.raw_transactions" \
  ./raw_transactions_10000.csv \
  transaction_id:STRING,customer_id:STRING,signup_date:STRING,purchase_date:STRING,amount:STRING,item_category:STRING,is_returned:STRING
