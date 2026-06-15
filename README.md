# Retail Medallion Pipeline - BigQuery

A raw retail file with 10,000 transactions. Some dates missing. Some amounts negative. Some nulls stored as the literal string 'NULL', which a naive COALESCE will walk straight past without flinching.

This pipeline takes that file through a Bronze-Silver-Gold architecture in BigQuery, ending in a k-means segmentation in BQML. Each layer handles one class of problem.

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

Before writing any transformation I ran profiling queries against the Bronze table. Four things stood out.

The first was that the nulls were not empty cells. Both `signup_date` and `is_returned` carried the literal string 'NULL'. A naive `COALESCE` does nothing here, because the value is not actually null. `NULLIF` has to come first, or the broken rows pass through silently.

The second was that the 407 negative amounts were not refunds. Cross-tabbing them against `is_returned` shows 282 with `is_returned = FALSE`. These are corrupt records, not reversals. Safe to delete.

The third was that `signup_date` is not a customer attribute. 2,681 customers have more than one distinct signup date across their rows, and the gap between signup and purchase has a hard ceiling at 30 days. The generator created `signup_date` per transaction, not per customer. So `days_to_first_purchase` as the brief defines it is a per-row gap, not a true first-purchase metric. I built it as specified and noted the limitation in the SQL.

The fourth was that the data is uniform throughout. Flat monthly volume, flat 20% return rate across all six categories, amounts roughly uniform between 0 and 1,200. K-means will converge, but the clusters will reflect the feature space, not natural customer segments. I'd treat that differently next time, aggregating to customer grain first (total spend, dominant category, return rate) before clustering.

## Pipeline layers

The Medallion Architecture is a way of separating data quality into three stages. Raw lands in Bronze. Cleaned and typed data lives in Silver. Analytics-ready output sits in Gold. Each layer reads from the one below it and writes a new table, so the original raw file is never overwritten and every transformation is reproducible.

**Bronze.** The CSV is loaded into `retail_bronze.raw_transactions` with an explicit all-STRING schema. Autodetect would mistype the literal 'NULL' values, so the schema is declared deliberately. Nothing is cleaned at this stage; the goal is faithful capture.

**Silver.** `retail_silver.cleaned_transactions` strips the literal NULL strings with `NULLIF` before any coalesce, filters amounts of zero or below, casts the types, and engineers `days_to_first_purchase`. 10,000 rows in, 9,593 out.

**Gold.** A k-means model is trained in `retail_gold` with `k=6` to match the six categories. `ML.PREDICT` runs against Silver, BigQuery assigns each transaction to one of the six clusters, and the results are joined back to the clean transaction columns in `retail_gold.analytics_customer_segments`.

## Repo structure

```
retail-project/
├── setup.sh                # creates the three datasets and loads the raw CSV into Bronze
├── sql/                    # standalone SQL scripts that build each layer
├── orchestration/          # Dataform files that wire the layers into a scheduled DAG
├── proof/                  # screenshots of execution, schema, and model evaluation
├── package.json            # Dataform dependency declaration
├── dataform.json           # Dataform project settings (warehouse, default datasets)
└── README.md
```

## SQL scripts (`/sql`)

All transformation logic lives in `/sql`. Each script is standalone and can be run directly in the BigQuery console, in order.

- **`bronze_profiling.sql`**: EDA against the raw Bronze table before any transformation was written.
  - 14 short queries, each with a comment explaining what it checks and what it found.
  - Covers row counts, duplicate checks, the literal-NULL discovery, the negative-amount cross-tab against `is_returned`, the per-transaction `signup_date` finding, monthly volume, and return rate.
  - The point of this file is to show that every transformation decision downstream was made against evidence rather than assumption.

- **`silver_transform.sql`**: builds the cleansed Silver table.
  - Reads from Bronze, applies the `NULLIF` then `COALESCE` pattern to the literal NULL strings.
  - Casts dates to DATE, amounts to NUMERIC, and defaults missing `is_returned` values to FALSE.
  - Filters out rows where `amount <= 0`.
  - Engineers the `days_to_first_purchase` column, with comments flagging the per-row grain caveat.

- **`gold_model_training.sql`**: creates the BQML k-means model with `CREATE OR REPLACE MODEL`.
  - Six clusters, `amount` and `item_category` as features.
  - `STANDARDIZE_FEATURES = TRUE` so that `amount` (which spans 0 to 1,200) doesn't drown out the one-hot encoded category column.
  - Output: `retail_gold.customer_segment_model`, inspectable via the Evaluation tab in the BigQuery console.

- **`gold_prediction.sql`**: applies the trained model to Silver and writes the final analytics table.
  - Calls `ML.PREDICT` against `customer_segment_model`.
  - Joins the cluster assignments back to the clean transaction columns.
  - Output: `retail_gold.analytics_customer_segments`. Every row from Silver, plus a `customer_segment` column indicating which of the six clusters it belongs to.

## Orchestration (`/orchestration`)

For a pipeline of this size I used Dataform. Dataform is BigQuery's native orchestration tool. You declare your tables as SQLX files, Dataform reads the dependencies between them, builds a DAG, and runs it on a schedule. It's free, it lives inside BigQuery, and it supports assertions: lightweight data quality checks that run between steps and fail the pipeline if the data doesn't look right.

The files in `/orchestration` are the live Dataform project, committed here as a static copy so a reviewer can read them without opening the GCP console.

- **`workflow_settings.yaml`**: project-level settings. Which GCP project to write to, the default dataset for Dataform's internal tables, and the Dataform core version.

- **`sources.js`**: declares the Bronze table as a source. Dataform doesn't manage Bronze (it was loaded by `setup.sh`), but it needs to know the table exists so it can build the dependency graph from it.

- **`cleaned_transactions.sqlx`**: the Silver step. Contains the same transformation logic as `sql/silver_transform.sql` in Dataform's SQLX format. The `config` block adds two assertions: a `nonNull` check on the key columns, and a `rowConditions` check that `amount > 0`. If either fails, the pipeline halts before Gold runs.

- **`analytics_customer_segments.sqlx`**: the Gold step. Depends on the Silver table via Dataform's `ref()` function, calls `ML.PREDICT` against the model trained by `gold_model_training.sql`, and writes the final analytics table. Model training itself is not run by Dataform on every execution; it's a one-off script in `/sql`. The daily pipeline applies the trained model rather than retraining it.

A daily release configuration compiles the Dataform code from the `main` branch each morning; a daily workflow configuration executes all actions at 06:00 UTC.

## `setup.sh`

A short bash script that does the initial setup: creates the three datasets (`retail_bronze`, `retail_silver`, `retail_gold`) and loads `raw_transactions_10000.csv` into Bronze with an explicit all-STRING schema. It's idempotent in the sense that the `bq load --replace` flag will overwrite the table if it already exists. The CSV itself is not committed to the repo (see `.gitignore`); the reviewer can drop it into the project root before running.

## Proof of execution (`/proof`)

- `dataform_execution_success.png`: a successful Dataform workflow execution with all three actions and the assertion passing green
- `gold_schema.png`: the schema of `retail_gold.analytics_customer_segments` showing the nine columns and their types
- `gold_preview.png`: a row preview of the same table, confirming 9,593 rows and populated cluster assignments
- `model_evaluation.png`: the Evaluation tab of `customer_segment_model` showing the Davies-Bouldin index, mean squared distance, and the per-cluster centroid values

## AI usage

Claude (Anthropic) was used during this build. It assisted with the initial build plan and the structure and layout of this README. All SQL, profiling logic, and architectural decisions were written and made independently.