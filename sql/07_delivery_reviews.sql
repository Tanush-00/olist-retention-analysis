-- =====================================================================
-- 07_delivery_reviews.sql
-- Does late delivery hurt reviews, and does a bad first experience stop
-- customers from coming back?
-- Scope: delivered orders with a delivery date.
-- =====================================================================

-- name: delivery_overview
SELECT COUNT(*)                                   AS delivered_orders,
       ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
       ROUND(AVG(julianday(estimated_date) - julianday(purchase_date)), 1) AS avg_promised_days,
       SUM(is_late)                               AS late_orders,
       ROUND(100.0 * AVG(is_late), 2)             AS late_pct,
       ROUND(AVG(review_score), 2)                AS avg_review_score
FROM v_orders
WHERE is_delivered = 1;

-- name: review_by_delivery_status
SELECT CASE WHEN is_late = 1 THEN 'Late' ELSE 'On time / early' END AS delivery_status,
       COUNT(*)                                      AS orders,
       ROUND(AVG(review_score), 2)                   AS avg_review_score,
       ROUND(100.0 * AVG(review_score <= 2), 1)      AS pct_1_2_star,
       ROUND(100.0 * AVG(review_score = 5), 1)       AS pct_5_star
FROM v_orders
WHERE is_delivered = 1 AND review_score IS NOT NULL
GROUP BY delivery_status
ORDER BY delivery_status DESC;

-- name: review_by_delay_bucket
SELECT CASE WHEN delay_days <= -8 THEN '1. 8+ days early'
            WHEN delay_days <= -1 THEN '2. 1-7 days early'
            WHEN delay_days = 0   THEN '3. on estimated day'
            WHEN delay_days <= 3  THEN '4. 1-3 days late'
            WHEN delay_days <= 7  THEN '5. 4-7 days late'
            WHEN delay_days <= 14 THEN '6. 8-14 days late'
            ELSE '7. 15+ days late' END              AS delay_bucket,
       COUNT(*)                                      AS orders,
       ROUND(AVG(review_score), 2)                   AS avg_review_score,
       ROUND(100.0 * AVG(review_score <= 2), 1)      AS pct_1_2_star
FROM v_orders
WHERE is_delivered = 1 AND review_score IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;

-- name: late_rate_by_month
SELECT purchase_month,
       COUNT(*)                          AS delivered_orders,
       ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
       ROUND(100.0 * AVG(is_late), 1)    AS late_pct,
       ROUND(AVG(review_score), 2)       AS avg_review_score
FROM v_orders
WHERE is_delivered = 1
  AND purchase_month BETWEEN '2017-01' AND '2018-08'
GROUP BY purchase_month
ORDER BY purchase_month;

-- name: delivery_by_state
SELECT customer_state,
       COUNT(*)                          AS delivered_orders,
       ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
       ROUND(100.0 * AVG(is_late), 1)    AS late_pct,
       ROUND(AVG(freight_value), 2)      AS avg_freight,
       ROUND(AVG(review_score), 2)       AS avg_review_score
FROM v_orders
WHERE is_delivered = 1
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC;

-- name: first_order_late_vs_repeat
-- First purchases from Jan-2017 to Feb-2018 only, so every customer had
-- at least 6 months in the data to come back.
WITH first_orders AS (
    SELECT o.*,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                              ORDER BY purchase_ts, order_id) AS rn
    FROM v_orders o
)
SELECT CASE WHEN f.is_late = 1 THEN 'First order late'
            ELSE 'First order on time' END              AS first_order_experience,
       COUNT(*)                                         AS customers,
       SUM(c.n_purchase_days >= 2)                      AS came_back,
       ROUND(100.0 * AVG(c.n_purchase_days >= 2), 2)    AS repeat_rate_pct
FROM first_orders f
JOIN v_customers c ON c.customer_unique_id = f.customer_unique_id
WHERE f.rn = 1
  AND f.is_delivered = 1
  AND f.purchase_month BETWEEN '2017-01' AND '2018-02'
GROUP BY first_order_experience
ORDER BY first_order_experience;

-- name: first_review_vs_repeat
WITH first_orders AS (
    SELECT o.*,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                              ORDER BY purchase_ts, order_id) AS rn
    FROM v_orders o
)
SELECT f.review_score                                   AS first_order_review,
       COUNT(*)                                         AS customers,
       SUM(c.n_purchase_days >= 2)                      AS came_back,
       ROUND(100.0 * AVG(c.n_purchase_days >= 2), 2)    AS repeat_rate_pct
FROM first_orders f
JOIN v_customers c ON c.customer_unique_id = f.customer_unique_id
WHERE f.rn = 1
  AND f.review_score IS NOT NULL
  AND f.purchase_month BETWEEN '2017-01' AND '2018-02'
GROUP BY f.review_score
ORDER BY f.review_score;
