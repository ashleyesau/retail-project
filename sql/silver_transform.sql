-- Reads from retail_bronze.raw_transactions, cleans and transforms the data,
-- and writes to retail_silver.cleaned_transactions.

CREATE OR REPLACE TABLE `retail-project-499413.retail_silver.cleaned_transactions` AS

SELECT
  transaction_id,
  customer_id,

  -- Dates cast to DATE
  SAFE_CAST(purchase_date AS DATE) AS purchase_date,

  -- signup_date: strip the literal 'NULL' strings first, then coalesce to purchase_date
  COALESCE(
    NULLIF(signup_date, 'NULL'),
    purchase_date
  ) AS signup_date_raw,
  SAFE_CAST(
    COALESCE(NULLIF(signup_date, 'NULL'), purchase_date)
  AS DATE) AS signup_date,

  -- Amount cast to NUMERIC
  CAST(amount AS NUMERIC) AS amount,

  TRIM(item_category) AS item_category,

  -- is_returned: strip literal 'NULL' strings, default to FALSE
  CAST(
    COALESCE(NULLIF(is_returned, 'NULL'), 'FALSE')
  AS BOOL) AS is_returned,

  -- Per-row gap between signup and purchase
  -- Note: signup_date varies per transaction not per customer, so this is
  -- the per-row gap not days to a customer's true first purchase.
  DATE_DIFF(
    SAFE_CAST(purchase_date AS DATE),
    SAFE_CAST(COALESCE(NULLIF(signup_date, 'NULL'), purchase_date) AS DATE),
    DAY
  ) AS days_to_first_purchase

FROM `retail-project-499413.retail_bronze.raw_transactions`

-- Filter out invalid amounts
WHERE CAST(amount AS NUMERIC) > 0;

-- 10000 rows in, 9593 expected out after filtering negative amounts.
