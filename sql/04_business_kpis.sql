-- =====================================================================
-- 04_business_kpis.sql
-- Headline KPIs and growth trends.
-- Revenue = item price + freight of valid (non-canceled) orders, in BRL.
-- =====================================================================

-- name: headline_kpis
SELECT COUNT(*)                            AS total_orders,
       COUNT(DISTINCT customer_unique_id)  AS total_customers,
       ROUND(SUM(order_value), 0)          AS total_revenue,
       ROUND(AVG(order_value), 2)          AS avg_order_value,
       ROUND(AVG(n_items), 2)              AS avg_items_per_order,
       ROUND(AVG(review_score), 2)         AS avg_review_score,
       MIN(purchase_date)                  AS first_order_date,
       MAX(purchase_date)                  AS last_order_date
FROM v_orders;

-- name: monthly_trend
-- Full months only (Jan-2017 .. Aug-2018). LAG() gives month-over-month growth.
WITH monthly AS (
    SELECT purchase_month,
           COUNT(*)                           AS orders,
           COUNT(DISTINCT customer_unique_id) AS customers,
           SUM(order_value)                   AS revenue
    FROM v_orders
    WHERE purchase_month BETWEEN '2017-01' AND '2018-08'
    GROUP BY purchase_month
)
SELECT purchase_month,
       orders,
       customers,
       ROUND(revenue, 0)                                          AS revenue,
       ROUND(revenue / orders, 2)                                 AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY purchase_month))
             / LAG(revenue) OVER (ORDER BY purchase_month), 1)    AS revenue_mom_pct
FROM monthly
ORDER BY purchase_month;

-- name: yoy_jan_aug
-- Same 8 months in both years -> fair year-over-year comparison
WITH by_year AS (
    SELECT substr(purchase_month, 1, 4) AS year,
           COUNT(*)                     AS orders,
           SUM(order_value)             AS revenue
    FROM v_orders
    WHERE substr(purchase_month, 6, 2) BETWEEN '01' AND '08'
      AND substr(purchase_month, 1, 4) IN ('2017', '2018')
    GROUP BY year
)
SELECT year,
       orders,
       ROUND(revenue, 0)                                                   AS revenue,
       ROUND(revenue / orders, 2)                                          AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY year))
             / LAG(revenue) OVER (ORDER BY year), 1)                       AS revenue_growth_pct,
       ROUND(100.0 * (orders - LAG(orders) OVER (ORDER BY year))
             / LAG(orders) OVER (ORDER BY year), 1)                        AS order_growth_pct
FROM by_year
ORDER BY year;

-- name: revenue_by_state
SELECT customer_state,
       COUNT(*)                                                     AS orders,
       ROUND(SUM(order_value), 0)                                   AS revenue,
       ROUND(100.0 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 1) AS revenue_share_pct,
       ROUND(AVG(order_value), 2)                                   AS avg_order_value,
       ROUND(AVG(freight_value), 2)                                 AS avg_freight
FROM v_orders
GROUP BY customer_state
ORDER BY revenue DESC;

-- name: orders_by_weekday
SELECT CAST(strftime('%w', purchase_ts) AS INTEGER) AS weekday_num,   -- 0 = Sunday
       CASE strftime('%w', purchase_ts)
            WHEN '0' THEN 'Sun' WHEN '1' THEN 'Mon' WHEN '2' THEN 'Tue'
            WHEN '3' THEN 'Wed' WHEN '4' THEN 'Thu' WHEN '5' THEN 'Fri'
            ELSE 'Sat' END                          AS weekday,
       COUNT(*)                                     AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM v_orders
GROUP BY weekday_num
ORDER BY weekday_num;

-- name: payment_mix
SELECT payment_type,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
       ROUND(AVG(order_value), 2)                          AS avg_order_value,
       ROUND(AVG(payment_installments), 1)                 AS avg_installments
FROM v_orders
WHERE payment_type IS NOT NULL
GROUP BY payment_type
ORDER BY orders DESC;
