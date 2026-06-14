# Retail Medallion Pipeline - BigQuery

- A Bronze to Gold data pipeline built entirely in BigQuery.
- The raw file contains messy retail transaction data: missing dates, corrupt amounts, and no structure.
- Each layer fixes one class of problem until the data is clean enough to answer a business question: which customers behave alike?

## The dataset

10,000 synthetic retail transactions across 4,861 customers, January 2025 to February 2026.

Seven columns:
1. transaction_id
2. customer_id
3. signup_date
4. purchase_date
5. amount
6. item_category
7. is_returned

## What I found in the data

Before writing any transformation I ran profiling queries against the Bronze table in BigQuery. Four things stood out.

**The null values are not empty cells.**
- Both signup_date and is_returned contain the literal string 'NULL'.
- A naive COALESCE does nothing because the value is not actually null.
- NULLIF is required first, otherwise the broken rows pass through silently.

**The 407 negative amounts are not refunds.**
- Cross-tabbing them against is_returned shows 282 have is_returned = FALSE.
- These are corrupt records, not reversals.
- Safe to delete.

**signup_date is not a customer attribute.**
- 2,681 customers have more than one distinct signup date across their rows.
- The gap between signup and purchase has a hard ceiling at 30 days.
- So the generator created signup_date per transaction, not per customer.
- This means days_to_first_purchase is the per-row gap, not a true first-purchase metric. I built it as the brief specifies and noted the limitation.

**The data is uniform throughout.**
- Flat monthly volume, flat 20% return rate across all six categories, amounts roughly uniform between 0 and 1,200.
- K-means will converge, but the clusters reflect the feature space, not natural customer segments.
- A production version would aggregate to customer grain first (total spend, dominant category, return rate) before clustering.

## Pipeline layers

**Bronze: raw ingestion.**
- The CSV is loaded into retail_bronze.raw_transactions with an explicit all-STRING schema.
- No autodetect: it can misread the literal 'NULL' strings in typed columns.

**Silver: cleansing and transformation.**
- retail_silver.cleaned_transactions handles the literal NULL strings with NULLIF before any coalesce logic.
- Filters amounts less than or equal to zero, casts all types, and engineers days_to_first_purchase.
- 10,000 rows in, 9,593 out.

**Gold: segmentation.**
- A k-means model (k=6, matching the six product categories) is trained in retail_gold using BQML.
- ML.PREDICT is applied to the Silver data.
- The results are joined back to the clean transaction columns in retail_gold.analytics_customer_segments.

## SQL scripts

All transformation logic lives in /sql:

- bronze_profiling.sql: warehouse EDA run against the raw Bronze table before any transformation
- silver_transform.sql: the cleansing and transformation script
- gold_model_training.sql: CREATE OR REPLACE MODEL for the k-means clustering model
- gold_prediction.sql: ML.PREDICT applied to Silver, writing the final Gold table

## Orchestration

For a pipeline of this size I used Dataform, and the /orchestration folder contains the working setup. The three steps have a clear dependency order. Silver depends on Bronze, Gold depends on Silver. Dataform expresses that as a DAG natively inside BigQuery at no extra cost, with assertions to catch data quality problems between layers. A daily release configuration compiles the code from the main branch each morning and a daily workflow configuration executes all actions at 06:00 UTC.

## Proof of execution

Screenshots of the final table schema, row preview, model evaluation metrics, and Dataform DAG are in /proof.

## AI usage

Claude (Anthropic) was used during this build. It assisted with the initial build plan and the structure and layout of this README.
