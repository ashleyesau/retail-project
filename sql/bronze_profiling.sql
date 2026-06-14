-- Warehouse EDA against the raw Bronze table before any transformation.
-- Each query states what it checks and what it found.

-- Row count and duplicate check
SELECT
  COUNT(*)                        AS total_rows,
  COUNT(DISTINCT transaction_id)  AS distinct_transactions
FROM `retail-project-499413.retail_bronze.raw_transactions`;
-- 10000 rows, 10000 distinct. No duplicates.

-- Check whether null signup dates are empty cells or literal 'NULL' strings
SELECT
  COUNT(*) AS signup_null_strings
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE signup_date = 'NULL';
-- 823 literal 'NULL' strings. NULLIF needed before COALESCE.

-- Same check on is_returned
SELECT
  COUNT(*) AS is_returned_null_strings
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE is_returned = 'NULL';
-- 1009 literal 'NULL' strings.

-- Check for empty or whitespace-only values across all columns
SELECT
  COUNTIF(TRIM(transaction_id) = '')  AS blank_transaction_id,
  COUNTIF(TRIM(customer_id) = '')     AS blank_customer_id,
  COUNTIF(TRIM(signup_date) = '')     AS blank_signup_date,
  COUNTIF(TRIM(purchase_date) = '')   AS blank_purchase_date,
  COUNTIF(TRIM(amount) = '')          AS blank_amount,
  COUNTIF(TRIM(item_category) = '')   AS blank_item_category,
  COUNTIF(TRIM(is_returned) = '')     AS blank_is_returned
FROM `retail-project-499413.retail_bronze.raw_transactions`;
-- All zero.

-- Invalid amounts and whether they are refunds or corrupt records
SELECT
  COUNTIF(CAST(amount AS FLOAT64) <= 0)                          AS amount_lte_zero,
  COUNTIF(CAST(amount AS FLOAT64) = 0)                           AS amount_exactly_zero,
  MIN(CAST(amount AS FLOAT64))                                   AS min_amount,
  COUNTIF(CAST(amount AS FLOAT64) < 0 AND is_returned = 'FALSE') AS negative_not_returned
FROM `retail-project-499413.retail_bronze.raw_transactions`;
-- 407 amounts <= 0, none exactly zero, min -149.65.
-- 282 of 407 have is_returned = FALSE so these are corrupt records not refunds.

-- Confirm date columns parse cleanly before casting
SELECT
  COUNTIF(SAFE_CAST(signup_date AS DATE) IS NULL
    AND signup_date != 'NULL')         AS signup_date_parse_failures,
  COUNTIF(SAFE_CAST(purchase_date AS DATE) IS NULL) AS purchase_date_parse_failures
FROM `retail-project-499413.retail_bronze.raw_transactions`;
-- Zero parse failures on both columns.

-- Check for signup dates that fall after the purchase date
SELECT
  COUNT(*) AS signup_after_purchase
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE signup_date != 'NULL'
  AND SAFE_CAST(signup_date AS DATE) > SAFE_CAST(purchase_date AS DATE);
-- Zero.

-- Category values and distribution
SELECT
  item_category,
  COUNT(*) AS row_count
FROM `retail-project-499413.retail_bronze.raw_transactions`
GROUP BY item_category
ORDER BY row_count DESC;
-- 6 categories: Automotive, Apparel, Sports, Electronics, Beauty, Home. No variants.

-- Check whether signup_date is per customer or per transaction
SELECT
  COUNT(*) AS customers_with_multiple_signup_dates
FROM (
  SELECT customer_id
  FROM `retail-project-499413.retail_bronze.raw_transactions`
  WHERE signup_date != 'NULL'
  GROUP BY customer_id
  HAVING COUNT(DISTINCT signup_date) > 1
);
-- 2681 customers have more than one signup date.
-- signup_date varies per transaction, not per customer.
-- days_to_first_purchase will be the per-row gap, not a true first-purchase metric.

-- Of customers with NULL signups, how many have a real date on another row
SELECT
  COUNT(DISTINCT customer_id) AS null_signup_customers_with_real_signup_elsewhere
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE signup_date != 'NULL'
  AND customer_id IN (
    SELECT DISTINCT customer_id
    FROM `retail-project-499413.retail_bronze.raw_transactions`
    WHERE signup_date = 'NULL'
  );
-- 605 of the affected customers have a real signup date on another row.
-- Following the brief's coalesce rule. In production I would impute from
-- the customer's earliest known signup date.

-- Purchase date range
SELECT
  MIN(SAFE_CAST(purchase_date AS DATE)) AS earliest_purchase,
  MAX(SAFE_CAST(purchase_date AS DATE)) AS latest_purchase
FROM `retail-project-499413.retail_bronze.raw_transactions`;
-- 2025-01-01 to 2026-02-28.

-- Amount distribution across valid rows
SELECT
  APPROX_QUANTILES(CAST(amount AS FLOAT64), 4) AS amount_quartiles
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE CAST(amount AS FLOAT64) > 0;
-- Roughly uniform 0 to 1200, median around 580.

-- signup-to-purchase gap range
SELECT
  MIN(DATE_DIFF(SAFE_CAST(purchase_date AS DATE), SAFE_CAST(signup_date AS DATE), DAY)) AS min_gap,
  MAX(DATE_DIFF(SAFE_CAST(purchase_date AS DATE), SAFE_CAST(signup_date AS DATE), DAY)) AS max_gap
FROM `retail-project-499413.retail_bronze.raw_transactions`
WHERE signup_date != 'NULL';
-- Min 0, max 30. Hard ceiling at 30 confirms signup_date was generated per transaction.

-- Monthly volume and return rate
-- Flat across the board, so k-means will find arbitrary slices not natural segments.
SELECT
  FORMAT_DATE('%Y-%m', SAFE_CAST(purchase_date AS DATE)) AS month,
  COUNT(*)                                                AS transactions,
  COUNTIF(is_returned = 'TRUE')                          AS returned,
  ROUND(COUNTIF(is_returned = 'TRUE') / COUNT(*), 3)    AS return_rate
FROM `retail-project-499413.retail_bronze.raw_transactions`
GROUP BY month
ORDER BY month;
-- ~750 transactions per month, return rate flat at ~20% throughout.
