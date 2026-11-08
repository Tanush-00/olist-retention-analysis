-- =====================================================================
-- 06_rfm_segmentation.sql
-- RFM = Recency, Frequency, Monetary.
--   R score: NTILE(5) on days since last purchase (5 = most recent)
--   M score: NTILE(5) on total spend            (5 = top spenders)
--   F score: purchase days (1, 2, 3+). Quintiles do not work for F here
--            because almost every customer has bought exactly once.
-- Reference date = day after the last order in the dataset.
-- =====================================================================

-- name: build_rfm_table
DROP TABLE IF EXISTS rfm_customers;
CREATE TABLE rfm_customers AS
WITH ref AS (
    SELECT julianday(DATE(MAX(purchase_ts))) + 1 AS ref_day FROM v_orders
),
base AS (
    SELECT c.customer_unique_id,
           c.customer_state,
           CAST(ref.ref_day - julianday(DATE(c.last_purchase_ts)) AS INTEGER) AS recency_days,
           c.n_purchase_days                                                AS frequency,
           c.total_spend                                                    AS monetary
    FROM v_customers c
    CROSS JOIN ref
    WHERE c.total_spend IS NOT NULL
),
scored AS (
    SELECT *,
           6 - NTILE(5) OVER (ORDER BY recency_days) AS r_score,
           CASE WHEN frequency >= 3 THEN 3
                WHEN frequency = 2  THEN 2
                ELSE 1 END                          AS f_score,
           NTILE(5) OVER (ORDER BY monetary)        AS m_score
    FROM base
)
SELECT *,
       CASE WHEN f_score >= 2 AND r_score >= 4 THEN 'Champions'
            WHEN f_score >= 2                   THEN 'Loyal - Lapsing'
            WHEN r_score >= 4 AND m_score >= 4  THEN 'High-Value New'
            WHEN r_score >= 4                   THEN 'New - Low Spend'
            WHEN r_score = 3                    THEN 'Need Attention'
            WHEN m_score >= 4                   THEN 'At Risk - High Value'
            ELSE 'Lost - Low Value' END         AS segment
FROM scored;

-- name: rfm_segment_summary
SELECT segment,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_customers,
       ROUND(AVG(recency_days), 0)                                  AS avg_recency_days,
       ROUND(AVG(frequency), 2)                                     AS avg_frequency,
       ROUND(AVG(monetary), 2)                                      AS avg_spend,
       ROUND(SUM(monetary), 0)                                      AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue
FROM rfm_customers
GROUP BY segment
ORDER BY revenue DESC;

-- name: rfm_score_thresholds
-- What each R and M score actually means in days / BRL
SELECT 'recency_days' AS metric, r_score AS score,
       MIN(recency_days) AS min_value, MAX(recency_days) AS max_value, COUNT(*) AS customers
FROM rfm_customers GROUP BY r_score
UNION ALL
SELECT 'monetary_brl', m_score, MIN(monetary), MAX(monetary), COUNT(*)
FROM rfm_customers GROUP BY m_score
ORDER BY metric, score;
