/* ============================================================================
   SWT Berlin 2026 - Cortex Code demo
   Script 03 - Expanded RAW source data
   ----------------------------------------------------------------------------
   Adds 8 new source tables across e-commerce, support, and marketing domains.
   Run as SYSADMIN AFTER 02_setup_raw_data.sql.

   New tables:
     RAW_PRODUCT_CATEGORIES  -> product category hierarchy
     RAW_PRODUCTS            -> product catalog
     RAW_PAYMENTS            -> payment transactions per order
     RAW_SHIPMENTS           -> shipping/delivery per order
     RAW_PROMOTIONS          -> promo codes
     RAW_SUPPORT_TICKETS     -> customer support tickets
     RAW_CAMPAIGNS           -> marketing campaigns
     RAW_CAMPAIGN_EVENTS     -> impressions, clicks, conversions
   ============================================================================ */

USE ROLE SYSADMIN;
USE WAREHOUSE ADAPTIVE_WH;
USE DATABASE SWT_BERLIN_2026;
USE SCHEMA PUBLIC;

/* ----------------------------------------------------------------------------
   RAW_PRODUCT_CATEGORIES - 15 categories
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_PRODUCT_CATEGORIES AS
SELECT
    seq4() + 1 AS category_id,
    ARRAY_CONSTRUCT(
        'Electronics','Clothing','Home & Garden','Sports','Books',
        'Toys','Beauty','Automotive','Food & Beverage','Health',
        'Office Supplies','Pet Supplies','Jewelry','Music','Gaming'
    )[seq4()]::STRING AS category_name,
    CASE
        WHEN seq4() < 5 THEN 'High Margin'
        WHEN seq4() < 10 THEN 'Medium Margin'
        ELSE 'Low Margin'
    END AS margin_tier
FROM TABLE(GENERATOR(ROWCOUNT => 15));


/* ----------------------------------------------------------------------------
   RAW_PRODUCTS - 200 products across categories
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_PRODUCTS AS
SELECT
    seq4() + 1 AS product_id,
    'Product ' || (seq4() + 1) AS product_name,
    UNIFORM(1, 15, RANDOM()) AS category_id,
    ROUND(UNIFORM(5, 500, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS list_price,
    ROUND(UNIFORM(2, 250, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS cost_price,
    DATEADD(day, -UNIFORM(60, 800, RANDOM()), CURRENT_DATE()) AS created_date,
    CASE WHEN UNIFORM(1, 100, RANDOM()) <= 90 THEN TRUE ELSE FALSE END AS is_active
FROM TABLE(GENERATOR(ROWCOUNT => 200));


/* ----------------------------------------------------------------------------
   RAW_PAYMENTS - ~5,500 payments (most orders have 1 payment, some have 2)
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_PAYMENTS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY order_id, payment_seq) AS payment_id,
    order_id,
    payment_seq,
    ARRAY_CONSTRUCT('Credit Card','Debit Card','PayPal','Wire Transfer','Gift Card')[UNIFORM(0,4,RANDOM())]::STRING AS payment_method,
    payment_amount,
    DATEADD(minute, UNIFORM(0, 1440, RANDOM()), o.order_date) AS payment_date,
    CASE WHEN UNIFORM(1,100,RANDOM()) <= 95 THEN 'SUCCESS' ELSE 'FAILED' END AS payment_status
FROM (
    SELECT order_id, order_date, amount,
           1 AS payment_seq,
           CASE WHEN UNIFORM(1,100,RANDOM()) <= 85
                THEN amount
                ELSE ROUND(amount * UNIFORM(40,60,RANDOM())/100.0, 2)
           END AS payment_amount
    FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS
    UNION ALL
    SELECT order_id, order_date, amount,
           2 AS payment_seq,
           ROUND(amount * UNIFORM(40,60,RANDOM())/100.0, 2) AS payment_amount
    FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS
    WHERE UNIFORM(1,100,RANDOM()) <= 15
) o;


/* ----------------------------------------------------------------------------
   RAW_SHIPMENTS - ~4,200 shipments (completed + pending orders that ship)
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_SHIPMENTS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY o.order_id) AS shipment_id,
    o.order_id,
    DATEADD(day, UNIFORM(0, 3, RANDOM()), o.order_date) AS shipped_date,
    DATEADD(day, UNIFORM(3, 14, RANDOM()), o.order_date) AS delivered_date,
    ARRAY_CONSTRUCT('Standard','Express','Overnight','Economy')[UNIFORM(0,3,RANDOM())]::STRING AS shipping_method,
    ARRAY_CONSTRUCT('FedEx','UPS','DHL','USPS')[UNIFORM(0,3,RANDOM())]::STRING AS carrier,
    ROUND(UNIFORM(3, 25, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS shipping_cost
FROM SWT_BERLIN_2026.PUBLIC.RAW_ORDERS o
WHERE o.status IN ('COMPLETED', 'PENDING')
  AND UNIFORM(1, 100, RANDOM()) <= 90;


/* ----------------------------------------------------------------------------
   RAW_PROMOTIONS - 30 promo codes
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_PROMOTIONS AS
SELECT
    seq4() + 1 AS promotion_id,
    'PROMO' || LPAD((seq4() + 1)::STRING, 3, '0') AS promo_code,
    ARRAY_CONSTRUCT('Percentage','Fixed Amount','Free Shipping','Buy One Get One')[UNIFORM(0,3,RANDOM())]::STRING AS discount_type,
    CASE
        WHEN UNIFORM(0,3,RANDOM()) = 0 THEN UNIFORM(5, 50, RANDOM())
        ELSE UNIFORM(10, 100, RANDOM())
    END AS discount_value,
    DATEADD(day, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE()) AS start_date,
    DATEADD(day, UNIFORM(14, 90, RANDOM()),
            DATEADD(day, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE())) AS end_date,
    UNIFORM(0, 500, RANDOM()) AS min_order_amount
FROM TABLE(GENERATOR(ROWCOUNT => 30));


/* ----------------------------------------------------------------------------
   RAW_SUPPORT_TICKETS - ~800 tickets
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_SUPPORT_TICKETS AS
SELECT
    seq4() + 1 AS ticket_id,
    UNIFORM(1, 500, RANDOM()) AS customer_id,
    CASE WHEN UNIFORM(1,100,RANDOM()) <= 70
         THEN UNIFORM(1, 5000, RANDOM())
         ELSE NULL
    END AS order_id,
    ARRAY_CONSTRUCT('Billing','Shipping','Product Quality','Returns','Account','Technical')[UNIFORM(0,5,RANDOM())]::STRING AS category,
    ARRAY_CONSTRUCT('Low','Medium','High','Critical')[UNIFORM(0,3,RANDOM())]::STRING AS priority,
    ARRAY_CONSTRUCT('Open','In Progress','Resolved','Closed')[UNIFORM(0,3,RANDOM())]::STRING AS status,
    DATEADD(day, -UNIFORM(0, 365, RANDOM()), CURRENT_DATE()) AS created_at,
    CASE WHEN UNIFORM(1,100,RANDOM()) <= 75
         THEN DATEADD(hour, UNIFORM(1, 168, RANDOM()),
                      DATEADD(day, -UNIFORM(0, 365, RANDOM()), CURRENT_DATE()))
         ELSE NULL
    END AS resolved_at,
    UNIFORM(1, 5, RANDOM()) AS satisfaction_score
FROM TABLE(GENERATOR(ROWCOUNT => 800));


/* ----------------------------------------------------------------------------
   RAW_CAMPAIGNS - 20 marketing campaigns
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_CAMPAIGNS AS
SELECT
    seq4() + 1 AS campaign_id,
    'Campaign ' || (seq4() + 1) AS campaign_name,
    ARRAY_CONSTRUCT('Email','Social Media','Paid Search','Display','Affiliate','Influencer')[UNIFORM(0,5,RANDOM())]::STRING AS channel,
    ROUND(UNIFORM(1000, 50000, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS budget,
    ROUND(UNIFORM(500, 45000, RANDOM()) + UNIFORM(0, 99, RANDOM())/100.0, 2) AS spend,
    DATEADD(day, -UNIFORM(14, 365, RANDOM()), CURRENT_DATE()) AS start_date,
    DATEADD(day, UNIFORM(7, 60, RANDOM()),
            DATEADD(day, -UNIFORM(14, 365, RANDOM()), CURRENT_DATE())) AS end_date,
    ARRAY_CONSTRUCT('North America','EMEA','APAC','LATAM')[UNIFORM(0,3,RANDOM())]::STRING AS target_region
FROM TABLE(GENERATOR(ROWCOUNT => 20));


/* ----------------------------------------------------------------------------
   RAW_CAMPAIGN_EVENTS - ~10,000 impressions/clicks/conversions
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SWT_BERLIN_2026.PUBLIC.RAW_CAMPAIGN_EVENTS AS
SELECT
    seq4() + 1 AS event_id,
    UNIFORM(1, 20, RANDOM()) AS campaign_id,
    CASE WHEN UNIFORM(1,100,RANDOM()) <= 60
         THEN UNIFORM(1, 500, RANDOM())
         ELSE NULL
    END AS customer_id,
    ARRAY_CONSTRUCT('impression','click','conversion')[
        CASE
            WHEN UNIFORM(1,100,RANDOM()) <= 70 THEN 0
            WHEN UNIFORM(1,100,RANDOM()) <= 85 THEN 1
            ELSE 2
        END
    ]::STRING AS event_type,
    DATEADD(second, -UNIFORM(0, 31536000, RANDOM()), CURRENT_TIMESTAMP()) AS event_timestamp,
    CASE
        WHEN UNIFORM(1,100,RANDOM()) <= 30 THEN 'mobile'
        WHEN UNIFORM(1,100,RANDOM()) <= 70 THEN 'desktop'
        ELSE 'tablet'
    END AS device_type
FROM TABLE(GENERATOR(ROWCOUNT => 10000));


/* ----------------------------------------------------------------------------
   Sanity checks
   ---------------------------------------------------------------------------- */
SELECT 'RAW_PRODUCT_CATEGORIES' AS table_name, COUNT(*) AS rows FROM SWT_BERLIN_2026.PUBLIC.RAW_PRODUCT_CATEGORIES
UNION ALL SELECT 'RAW_PRODUCTS',         COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_PRODUCTS
UNION ALL SELECT 'RAW_PAYMENTS',         COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_PAYMENTS
UNION ALL SELECT 'RAW_SHIPMENTS',        COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_SHIPMENTS
UNION ALL SELECT 'RAW_PROMOTIONS',       COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_PROMOTIONS
UNION ALL SELECT 'RAW_SUPPORT_TICKETS',  COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_SUPPORT_TICKETS
UNION ALL SELECT 'RAW_CAMPAIGNS',        COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_CAMPAIGNS
UNION ALL SELECT 'RAW_CAMPAIGN_EVENTS',  COUNT(*) FROM SWT_BERLIN_2026.PUBLIC.RAW_CAMPAIGN_EVENTS;
