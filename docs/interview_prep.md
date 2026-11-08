# Interview prep: how to present this project

> **Hinglish note:** Is project ko rata mat lagana. Har section ka *reason* samjho: humne `customer_unique_id` kyun use kiya, "late" ko kaise define kiya, z-test kyun lagaya. Interviewer numbers se zyada yeh dekhta hai ki tumne **decisions kaise liye**. Neeche ke answers English mein hain kyunki interview mein yahi bolna hai.

---

## Resume bullets (pick 2–3)

- Analyzed **99K+ e-commerce orders across 9 relational tables** using **SQL (CTEs, window functions)** and **Python (pandas)**. Found that **97.8% of customers never repurchase** and sized each +1 pp of repeat rate at **~R$150K revenue**.
- Built **cohort retention** and **RFM segmentation** models. Identified two one-time, high-spend segments (29K customers) holding **57% of revenue** as targets for second-purchase and win-back campaigns.
- Showed that late deliveries cut average review scores from **4.29 to 2.27** and lower repeat purchases by **32%** (two-proportion z-test, p = 0.001). Traced **54% of late orders to 30% of sellers**.
- Built an **interactive 4-page dashboard** (HTML/Chart.js) and a **Power BI star-schema model with 20+ DAX measures** covering revenue, retention, delivery and seller KPIs.

> Power BI wala hissa resume pe tabhi likhna jab `dashboard/powerbi_guide.md` follow karke `.pbix` khud bana lo.

## 60-second pitch (STAR)

**Situation:** "Olist is a Brazilian marketplace. I used their public data: about 100,000 orders over two years, split across 9 tables."

**Task:** "I wanted to answer two business questions: why don't customers come back, and how much does late delivery hurt?"

**Action:** "I loaded everything into a SQL database and audited data quality first. For example, I found that `customer_id` changes with every order, so I used `customer_unique_id` to identify real customers. Then I built cohort retention and RFM segmentation in SQL with window functions, cross-checked the results in pandas, and used a two-proportion z-test to check whether late first orders really reduce repeat purchases."

**Result:** "97.8% of customers buy only once. Late orders get 2.3 stars instead of 4.3 and reduce repeat purchases by about a third. I recommended a second-purchase campaign for high-value new customers, a win-back campaign, and a seller SLA scorecard, since 30% of sellers cause over half of the delays. I sized a 1-point improvement in repeat rate at about R$150k."

## Likely questions and good answers

**Q: Why `customer_unique_id` instead of `customer_id`?**
In this dataset `customer_id` is generated per order, so every order looks like a new customer. Using it would make the repeat rate exactly 0%. 2,997 people have more than one `customer_id`.

**Q: How did you define a repeat customer?**
A customer who bought on **two or more different days**. 823 customers placed several orders on the same day. That is usually one basket split across sellers, not loyalty, so counting it would inflate retention.

**Q: How did you define "late"?**
Delivered on a later calendar day than the estimated delivery date. I compared dates, not timestamps, because the estimate has no time of day.

**Q: Some orders have several reviews. What did you do?**
I kept the most recent review per order using `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC)`.

**Q: Why did you exclude some months from trends?**
Sep–Dec 2016 and Sep–Oct 2018 have only a handful of orders (for example, 1 order in Dec-2016). Including them would create fake drops and spikes, so trends use Jan-2017 to Aug-2018.

**Q: Walk me through your cohort analysis.**
1. Find each customer's first purchase month (the cohort).
2. For every later purchase, compute months since the first one.
3. Count distinct active customers per cohort and month, then divide by cohort size.

Months that can't be observed yet (after Aug-2018) are left blank, not counted as zero.

**Q: Why not quintiles for Frequency in RFM?**
Almost every customer has F = 1, so NTILE(5) would split identical customers into different scores at random. I used F = 1, 2, 3+ instead and NTILE(5) for Recency and Monetary.

**Q: Is late delivery *causing* customers not to return?**
I can show an association, not causation. I limited the comparison to first orders from Jan-2017 to Feb-2018 so everyone had 6+ months to return, and the difference is statistically significant (z = 3.29, p = 0.001). Other factors (region, category) could still play a role. To prove causation you'd run an experiment, for example proactive delay alerts for a random half of late orders.

**Q: How did you check your SQL was correct?**
I re-computed the cohort table independently in pandas: the maximum difference was 0.005 percentage points (rounding). I also built a "check your numbers" table so the Power BI measures can be validated against the SQL totals.

**Q: What would you do with more time / data?**
A repurchase-propensity model to target the right customers; NLP on the Portuguese review comments to find *why* customers complain; a delivery-time prediction model to trigger delay alerts; and margin data to size impact in profit, not just revenue.

**Q: What was the hardest part?**
Data quality: per-order customer IDs, duplicate reviews, same-day split orders and thin edge months. Each would have quietly produced wrong numbers if I had jumped straight to charts.

## SQL concepts you can point to

| Concept | Where |
|---|---|
| Schema design, primary keys, indexes | `sql/01_schema.sql` |
| `NOT EXISTS` orphan checks, `UNION ALL` audit table | `sql/02_data_quality.sql` |
| Views as a clean semantic layer; `ROW_NUMBER()` de-duplication | `sql/03_clean_views.sql` |
| `LAG()` for MoM / YoY growth; `SUM() OVER ()` for shares | `sql/04_business_kpis.sql` |
| Multi-CTE cohort analysis; self-join for 2nd purchase | `sql/05_customer_retention.sql` |
| `NTILE()` scoring, `CASE` segmentation, `CREATE TABLE AS` | `sql/06_rfm_segmentation.sql` |
| Bucketing with `CASE`, conditional averages | `sql/07_delivery_reviews.sql` |
| Running totals `SUM() OVER (ORDER BY …)`, Pareto deciles | `sql/08_sellers_products.sql` |

## LinkedIn post (draft)

> 97.8% of customers on a Brazilian marketplace never ordered again. Here's what I found when I dug into 100K orders. 🧵
>
> I analyzed Olist's public e-commerce data (9 tables, 2016–2018) with SQL and Python:
> 📦 Late deliveries drop average reviews from 4.3★ to 2.3★
> 🔁 A late *first* order cuts the chance of a repeat purchase by 32%
> 💰 Repeat customers spend 2x more, so +1 point of repeat rate ≈ R$150K
> 🚚 30% of sellers cause 54% of late deliveries
>
> My recommendations: a second-purchase program in the first 90 days, proactive delay alerts, and a seller SLA scorecard.
>
> Full project (SQL, notebook, dashboard): [GitHub link]
> #DataAnalytics #SQL #Python #PowerBI
