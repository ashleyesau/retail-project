-- Trains a k-means clustering model on the silver cleaned data.
-- Features: amount and item_category.
-- k=6 to match the 6 product categories in the data.

CREATE OR REPLACE MODEL `retail-project-499413.retail_gold.customer_segment_model`
OPTIONS (
  model_type         = 'kmeans',
  num_clusters       = 6,
  standardize_features = TRUE
) AS

SELECT
  CAST(amount AS FLOAT64) AS amount,
  item_category
FROM `retail-project-499413.retail_silver.cleaned_transactions`;
