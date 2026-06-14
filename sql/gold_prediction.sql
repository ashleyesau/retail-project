-- Applies the k-means model to the silver data and writes the final
-- customer segments table to the gold layer.
-- Note: predictions are at transaction grain, not customer grain.
-- In production this would aggregate to customer level before clustering.

CREATE OR REPLACE TABLE `retail-project-499413.retail_gold.analytics_customer_segments` AS

SELECT
  t.transaction_id,
  t.customer_id,
  t.purchase_date,
  t.signup_date,
  t.amount,
  t.item_category,
  t.is_returned,
  t.days_to_first_purchase,
  p.CENTROID_ID AS customer_segment
FROM
  ML.PREDICT(
    MODEL `retail-project-499413.retail_gold.customer_segment_model`,
    (
      SELECT *
      FROM `retail-project-499413.retail_silver.cleaned_transactions`
    )
  ) AS p
JOIN `retail-project-499413.retail_silver.cleaned_transactions` AS t
  ON t.transaction_id = p.transaction_id;
