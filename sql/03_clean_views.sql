-- =====================================================================
-- 03_clean_views.sql
-- Cleaned, analysis-ready views. Every later script builds on these.
--
-- Cleaning decisions (from 02_data_quality.sql):
--   * Canceled / unavailable orders are excluded from revenue & customers.
--   * customer_id is per ORDER; customer_unique_id is the PERSON.
--     All customer metrics use customer_unique_id.
--   * Some orders have several reviews -> keep the most recent one.
--   * "Late" = delivered on a later calendar day than the estimate.
--   * Repeat customer = bought on 2+ different days. Several orders placed
--     the same day are usually one basket split by seller, not loyalty.
-- =====================================================================

-- name: v_order_items_agg
DROP VIEW IF EXISTS v_order_items_agg;
CREATE VIEW v_order_items_agg AS
SELECT order_id,
       COUNT(*)                  AS n_items,
       COUNT(DISTINCT seller_id) AS n_sellers,
       SUM(price)                AS product_value,
       SUM(freight_value)        AS freight_value
FROM order_items
GROUP BY order_id;

-- name: v_order_reviews
DROP VIEW IF EXISTS v_order_reviews;
CREATE VIEW v_order_reviews AS
SELECT order_id, review_score
FROM (
    SELECT order_id,
           review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_creation_date DESC,
                                       review_answer_timestamp DESC) AS rn
    FROM order_reviews
)
WHERE rn = 1;

-- name: v_order_payment_type
-- Main payment method of each order = the one that paid the most
DROP VIEW IF EXISTS v_order_payment_type;
CREATE VIEW v_order_payment_type AS
SELECT order_id, payment_type, payment_installments
FROM (
    SELECT order_id,
           payment_type,
           payment_installments,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY payment_value DESC, payment_sequential) AS rn
    FROM order_payments
)
WHERE rn = 1;

-- name: v_orders
-- One row per valid order with value, delivery and review metrics
DROP VIEW IF EXISTS v_orders;
CREATE VIEW v_orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_city,
       c.customer_state,
       o.order_status,
       o.order_purchase_timestamp                         AS purchase_ts,
       DATE(o.order_purchase_timestamp)                   AS purchase_date,
       strftime('%Y-%m', o.order_purchase_timestamp)      AS purchase_month,
       DATE(o.order_delivered_customer_date)              AS delivered_date,
       DATE(o.order_estimated_delivery_date)              AS estimated_date,
       i.n_items,
       i.n_sellers,
       ROUND(i.product_value, 2)                          AS product_value,
       ROUND(i.freight_value, 2)                          AS freight_value,
       ROUND(i.product_value + i.freight_value, 2)        AS order_value,
       pt.payment_type,
       pt.payment_installments,
       r.review_score,
       CASE WHEN o.order_status = 'delivered'
             AND o.order_delivered_customer_date IS NOT NULL
            THEN 1 ELSE 0 END                             AS is_delivered,
       ROUND(julianday(o.order_delivered_customer_date)
           - julianday(o.order_purchase_timestamp), 1)    AS delivery_days,
       CAST(julianday(DATE(o.order_delivered_customer_date))
          - julianday(DATE(o.order_estimated_delivery_date)) AS INTEGER) AS delay_days,
       CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
            WHEN DATE(o.order_delivered_customer_date)
               > DATE(o.order_estimated_delivery_date) THEN 1
            ELSE 0 END                                    AS is_late
FROM orders o
JOIN customers c                  ON c.customer_id = o.customer_id
LEFT JOIN v_order_items_agg i     ON i.order_id    = o.order_id
LEFT JOIN v_order_payment_type pt ON pt.order_id   = o.order_id
LEFT JOIN v_order_reviews r       ON r.order_id    = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');

-- name: v_customers
-- One row per real customer (customer_unique_id)
DROP VIEW IF EXISTS v_customers;
CREATE VIEW v_customers AS
SELECT customer_unique_id,
       MAX(customer_state)              AS customer_state,
       COUNT(*)                         AS n_orders,
       COUNT(DISTINCT purchase_date)    AS n_purchase_days,
       ROUND(SUM(order_value), 2)       AS total_spend,
       MIN(purchase_ts)                 AS first_purchase_ts,
       MAX(purchase_ts)                 AS last_purchase_ts,
       MIN(purchase_month)              AS cohort_month
FROM v_orders
GROUP BY customer_unique_id;

-- name: clean_view_row_counts
SELECT 'v_orders' AS view_name, COUNT(*) AS row_count FROM v_orders
UNION ALL SELECT 'v_customers', COUNT(*) FROM v_customers
UNION ALL SELECT 'v_orders (delivered)', SUM(is_delivered) FROM v_orders;
