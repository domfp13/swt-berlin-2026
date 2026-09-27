/* ============================================================================
   SWT Berlin 2026 - Cortex Code demo
   Script 02 - RAW source data  (run AFTER 01_database_setup.sql)
   ----------------------------------------------------------------------------
   Everything lives in SWT_BERLIN_2026.PUBLIC. Raw tables use the RAW_ prefix.

   Creates a synthetic e-commerce dataset: customers, orders, and refunds.

   Run as SYSADMIN.
   ============================================================================ */

USE ROLE SYSADMIN;
USE WAREHOUSE ADAPTIVE_WH;
USE DATABASE SWT_BERLIN_2026;
USE SCHEMA PUBLIC;

/* ----------------------------------------------------------------------------
   RAW_CUSTOMERS - 500 customers across 4 regions and 3 segments
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_CUSTOMERS AS
SELECT
    seq4() + 1                                                               AS customer_id,
    'Customer ' || (seq4() + 1)                                             AS customer_name,
    ARRAY_CONSTRUCT('North America','EMEA','APAC','LATAM')[UNIFORM(0,3,RANDOM())]::STRING AS region,
    ARRAY_CONSTRUCT('Enterprise','Mid-Market','SMB')[UNIFORM(0,2,RANDOM())]::STRING       AS segment,
    DATEADD(day, -UNIFORM(30, 1000, RANDOM()), CURRENT_DATE())               AS signup_date
FROM TABLE(GENERATOR(ROWCOUNT => 500));


/* ----------------------------------------------------------------------------
   RAW_ORDERS - 5,000 orders over the last ~18 months.
   A single RANDOM() draw per row (rnd) keeps the status distribution stable.
   Max order_date is intentionally a few days old so source freshness can be
   demonstrated as "stale".
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_ORDERS AS
SELECT
    order_id,
    customer_id,
    order_date,
    CASE
        WHEN rnd <= 85 THEN 'COMPLETED'
        WHEN rnd <= 95 THEN 'CANCELLED'
        ELSE 'PENDING'
    END                                                                      AS status,
    amount
FROM (
    SELECT
        seq4() + 1                                                           AS order_id,
        UNIFORM(1, 500, RANDOM())                                            AS customer_id,
        DATEADD(day, -UNIFORM(3, 540, RANDOM()), CURRENT_DATE())             AS order_date,
        UNIFORM(1, 100, RANDOM())                                            AS rnd,
        ROUND(UNIFORM(20, 2000, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS amount
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
);


/* ----------------------------------------------------------------------------
   RAW_REFUNDS - partial refunds on ~8% of COMPLETED orders older than 25 days
   (the 25-day floor keeps refund_date from landing in the future).
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_REFUNDS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY o.order_id)                                  AS refund_id,
    o.order_id,
    DATEADD(day, UNIFORM(1, 20, RANDOM()), o.order_date)                     AS refund_date,
    ROUND(o.amount * (UNIFORM(20, 100, RANDOM())/100.0), 2)                  AS refund_amount
FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS o
WHERE o.status = 'COMPLETED'
  AND o.order_date < DATEADD(day, -25, CURRENT_DATE())
  AND UNIFORM(1, 100, RANDOM()) <= 8;


/* ----------------------------------------------------------------------------
   Sanity checks
   ---------------------------------------------------------------------------- */
SELECT 'RAW_CUSTOMERS' AS table_name, COUNT(*) AS rows FROM SWT_BERLIN_2026.PUBLIC.RAW_CUSTOMERS
UNION ALL SELECT 'RAW_ORDERS',  COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS
UNION ALL SELECT 'RAW_REFUNDS', COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_REFUNDS;

-- Revenue by region preview (completed orders)
SELECT c.region,
       ROUND(SUM(o.amount), 2) AS gross_revenue
FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS o
JOIN SWT_BERLIN_2026.PUBLIC.RAW_CUSTOMERS c ON c.customer_id = o.customer_id
WHERE o.status = 'COMPLETED'
GROUP BY c.region
ORDER BY gross_revenue DESC;

-- Confirm freshness window (how old is the newest order?)
SELECT MAX(order_date) AS latest_order_date,
       DATEDIFF(day, MAX(order_date), CURRENT_DATE()) AS days_since_latest
FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS;
