"""
Step 2b - Stress-test the claim "a late first delivery lowers the repeat rate".

    python scripts/robustness_check.py

The SQL result 07_delivery_reviews__first_order_late_vs_repeat asks: did the customer *ever* buy again? It has a
weakness. A customer whose first order was in Jan-2017 had 20 months to come back, one from Feb-2018 only 7, and late
deliveries were most common in exactly the months with the shortest follow-up (Nov-2017 and Feb-2018). So part of the
gap could be a follow-up-time effect, not a delivery effect.

This script repeats the comparison in ways that remove that weakness and writes one row per variant to
outputs/robustness/first_order_late_vs_repeat.csv.

  A  original       first orders Jan-2017..Feb-2018, "ever bought again" (same numbers as the SQL result)
  B  equal window   same customers, "bought again within 180 days": everybody gets the same time to return
  C  early cohorts  first orders Jan-2017..Oct-2017 only (before the Nov-2017 and Feb-2018 delivery problems), 180 days
  D  stratified     B compared inside each first-order month, then combined (Mantel-Haenszel odds ratio)
  E  adjusted       logistic regression for B with first-order month, customer state and order value as controls

Needs the database from steps 1-2 (it reads the views v_orders and v_customers).
"""
import math
import sqlite3
import sys
from statistics import NormalDist

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf

from config import DB_PATH, ROBUSTNESS_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

WINDOW_DAYS = 180
COHORT_START, COHORT_END = "2017-01", "2018-02"       # same first-order months as the SQL result
EARLY_END = "2017-10"                                  # variant C stops before the Nov-2017 Black Friday delays

FIRST_ORDERS_SQL = """
WITH purchase_days AS (
    SELECT customer_unique_id, purchase_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_date) AS nth
    FROM (SELECT DISTINCT customer_unique_id, purchase_date FROM v_orders)
),
first_orders AS (
    SELECT customer_unique_id, customer_state, purchase_date, purchase_month, order_value,
           is_delivered, is_late,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS rn
    FROM v_orders
)
SELECT f.customer_unique_id, f.customer_state, f.purchase_date, f.purchase_month, f.order_value, f.is_late,
       CAST(julianday(p2.purchase_date) - julianday(f.purchase_date) AS INTEGER) AS days_to_second_purchase
FROM first_orders f
LEFT JOIN purchase_days p2 ON p2.customer_unique_id = f.customer_unique_id AND p2.nth = 2
WHERE f.rn = 1
  AND f.is_delivered = 1
  AND f.purchase_month BETWEEN ? AND ?
"""


def two_sided_p(z: float) -> float:
    return math.erfc(abs(z) / math.sqrt(2))


def compare(group, outcome: str) -> dict:
    """Late vs on-time first order: repeat rates, difference with 95% CI, relative change, two-proportion z-test."""
    late, on_time = group[group.late == 1], group[group.late == 0]
    n1, n0 = len(late), len(on_time)
    k1, k0 = int(late[outcome].sum()), int(on_time[outcome].sum())
    p1, p0 = k1 / n1, k0 / n0
    pooled = (k1 + k0) / (n1 + n0)
    z = (p0 - p1) / math.sqrt(pooled * (1 - pooled) * (1 / n1 + 1 / n0))
    se = math.sqrt(p1 * (1 - p1) / n1 + p0 * (1 - p0) / n0)
    diff = p1 - p0
    return {
        "customers_late": n1, "repeat_late": k1, "rate_late_pct": round(100 * p1, 2),
        "customers_on_time": n0, "repeat_on_time": k0, "rate_on_time_pct": round(100 * p0, 2),
        "diff_pp": round(100 * diff, 2), "diff_ci_low_pp": round(100 * (diff - 1.96 * se), 2),
        "diff_ci_high_pp": round(100 * (diff + 1.96 * se), 2),
        "relative_change_pct": round(100 * (p1 / p0 - 1), 1), "p_value": round(two_sided_p(z), 4),
    }


def mantel_haenszel(group, outcome: str, stratum: str) -> dict:
    """Odds ratio of repeating (late vs on time) combined over strata (Robins-Breslow-Greenland variance)."""
    num = den = 0.0
    parts = []
    for _, s in group.groupby(stratum):
        a = int(((s.late == 1) & (s[outcome] == 1)).sum())
        b = int(((s.late == 1) & (s[outcome] == 0)).sum())
        c = int(((s.late == 0) & (s[outcome] == 1)).sum())
        d = int(((s.late == 0) & (s[outcome] == 0)).sum())
        n = a + b + c + d
        if n == 0:
            continue
        num += a * d / n
        den += b * c / n
        parts.append((a, b, c, d, n))
    odds_ratio = num / den
    p_term = sum((a + d) / n * (a * d / n) for a, b, c, d, n in parts) / (2 * num ** 2)
    q_term = sum((a + d) / n * (b * c / n) + (b + c) / n * (a * d / n) for a, b, c, d, n in parts) / (2 * num * den)
    r_term = sum((b + c) / n * (b * c / n) for a, b, c, d, n in parts) / (2 * den ** 2)
    se_log = math.sqrt(p_term + q_term + r_term)
    return {"odds_ratio": round(odds_ratio, 2),
            "or_ci_low": round(math.exp(math.log(odds_ratio) - 1.96 * se_log), 2),
            "or_ci_high": round(math.exp(math.log(odds_ratio) + 1.96 * se_log), 2),
            "p_value": round(two_sided_p(math.log(odds_ratio) / se_log), 4)}


def logistic(group, outcome: str) -> dict:
    """Odds ratio for 'late first order' after controlling for first-order month, state and order value."""
    data = group.dropna(subset=["order_value"]).copy()
    top_states = data.customer_state.value_counts().index[:10]          # small states are merged into 'other'
    data["state"] = np.where(data.customer_state.isin(top_states), data.customer_state, "other")
    data["log_value"] = np.log(data.order_value.clip(lower=1))
    fit = smf.glm(f"{outcome} ~ late + C(purchase_month) + C(state) + log_value", data=data,
                  family=sm.families.Binomial()).fit()
    coef, se = fit.params["late"], fit.bse["late"]
    return {"odds_ratio": round(math.exp(coef), 2), "or_ci_low": round(math.exp(coef - 1.96 * se), 2),
            "or_ci_high": round(math.exp(coef + 1.96 * se), 2), "p_value": round(float(fit.pvalues["late"]), 4)}


def customers_needed(rate_on_time: float, rate_late: float) -> int:
    """Late-first-order customers needed (equal group sizes) for 80% power at the 5% level."""
    z_alpha, z_power = NormalDist().inv_cdf(0.975), NormalDist().inv_cdf(0.80)
    variance = rate_on_time * (1 - rate_on_time) + rate_late * (1 - rate_late)
    return math.ceil((z_alpha + z_power) ** 2 * variance / (rate_on_time - rate_late) ** 2)


def main() -> None:
    if not DB_PATH.exists():
        sys.exit("Database not found. Run scripts/load_data.py and scripts/run_sql.py first.")
    conn = sqlite3.connect(DB_PATH)
    try:
        df = pd.read_sql_query(FIRST_ORDERS_SQL, conn, params=(COHORT_START, COHORT_END))
        data_end = pd.Timestamp(conn.execute("SELECT MAX(purchase_date) FROM v_orders").fetchone()[0])
    finally:
        conn.close()
    df["late"] = df.is_late.astype(int)
    df["repeat_ever"] = df.days_to_second_purchase.notna().astype(int)
    df["repeat_window"] = (df.days_to_second_purchase <= WINDOW_DAYS).astype(int)   # no second purchase -> False -> 0
    early = df[df.purchase_month <= EARLY_END]
    df["follow_up_months"] = (data_end - pd.to_datetime(df.purchase_date)).dt.days / 30.44    # time each customer had to return

    rows = [
        {"variant": "A", "description": "original: first orders Jan-2017..Feb-2018, ever bought again",
         **compare(df, "repeat_ever")},
        {"variant": "B", "description": f"equal window: same customers, bought again within {WINDOW_DAYS} days",
         **compare(df, "repeat_window")},
        {"variant": "C", "description": f"early cohorts: first orders Jan-2017..Oct-2017, within {WINDOW_DAYS} days",
         **compare(early, "repeat_window")},
        {"variant": "D", "description": "stratified by first-order month (Mantel-Haenszel), within "
                                         f"{WINDOW_DAYS} days", **mantel_haenszel(df, "repeat_window", "purchase_month")},
        {"variant": "E", "description": "adjusted for first-order month, state and order value (logistic), within "
                                         f"{WINDOW_DAYS} days", **logistic(df, "repeat_window")},
    ]
    table = pd.DataFrame(rows)
    count_columns = ["customers_late", "repeat_late", "customers_on_time", "repeat_on_time"]
    table[count_columns] = table[count_columns].astype("Int64")                 # whole numbers, blank where not used
    ROBUSTNESS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = ROBUSTNESS_DIR / "first_order_late_vs_repeat.csv"
    table.to_csv(out_path, index=False)

    pd.set_option("display.width", 220)
    pd.set_option("display.max_columns", 30)
    pd.set_option("display.max_colwidth", 75)
    print(table[["variant", "description", "customers_late", "rate_late_pct", "rate_on_time_pct",
                 "relative_change_pct", "odds_ratio", "p_value"]].to_string(index=False))

    follow_up = df.groupby("late").follow_up_months.mean()
    print(f"\nAverage follow-up time (first order to {data_end:%d-%b-%Y}, when the data ends): "
          f"late first order {follow_up[1]:.1f} months, on time {follow_up[0]:.1f} months.")

    significant = int((table.p_value < 0.05).sum())
    lower = int((table.relative_change_pct.dropna() < 0).sum()) + int((table.odds_ratio.dropna() < 1).sum())
    needed = customers_needed(rows[1]["rate_on_time_pct"] / 100, rows[1]["rate_late_pct"] / 100)
    print(f"A late first order goes with a lower repeat rate in {lower} of {len(rows)} variants, "
          f"but p < 0.05 in only {significant} of {len(rows)}.")
    print(f"To detect the gap seen in variant B with 80% power, about {needed:,} late-first-order customers "
          f"would be needed; this data has {rows[1]['customers_late']:,}.")
    print(f"Saved {out_path}")


if __name__ == "__main__":
    main()
