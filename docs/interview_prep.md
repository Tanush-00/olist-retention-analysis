# Interview prep: how to present this project

> **Hinglish note:** Is project ko rata mat lagana. Har section ka *reason* samjho: humne `customer_unique_id` kyun use kiya, "late" ko kaise define kiya, z-test kyun lagaya. Interviewer numbers se zyada yeh dekhta hai ki tumne **decisions kaise liye**. Neeche ke answers English mein hain kyunki interview mein yahi bolna hai.

---

## Resume bullets (pick 2–3)

- Analyzed **99K+ e-commerce orders across 9 relational tables** using **SQL (CTEs, window functions)** and **Python (pandas)**. Found that **97.8% of customers never repurchase** and sized each +1 pp of repeat rate at **~R$150K revenue**.
- Built **cohort retention** and **RFM segmentation** models. Identified two one-time, high-spend segments (29K customers) holding **57% of revenue** as targets for second-purchase and win-back campaigns.
- Showed that late orders average **2.27 stars against 4.29** for on-time orders. Stress-tested the link to repeat purchases (a **32%** gap shrank to **21%**, p = 0.08, once every customer had the same follow-up time) and proposed an A/B test instead of claiming causation. Traced **54% of late orders to 30% of sellers**.
- Built an **interactive 4-page dashboard** (HTML/Chart.js) and a **Power BI star-schema model with 20+ DAX measures** covering revenue, retention, delivery and seller KPIs.

> Power BI wala hissa resume pe tabhi likhna jab `dashboard/powerbi_guide.md` follow karke `.pbix` khud bana lo.
>
> Bullet 3 mein 32% akela mat likhna. Pehle test mein p = 0.001 aaya tha, lekin barabar follow-up time dene par p = 0.08 hua. Interviewer ko dono batana (neeche Q&A dekho): isse dikhta hai ki tum apna hi result dobara test karte ho.

## 60-second pitch (STAR)

**Situation:** "Olist is a Brazilian marketplace. I used their public data: about 100,000 orders over two years, split across 9 tables."

**Task:** "I wanted to answer two business questions: why don't customers come back, and how much does late delivery hurt?"

**Action:** "I loaded everything into a SQL database and audited data quality first. For example, I found that `customer_id` changes with every order, so I used `customer_unique_id` to identify real customers. Then I built cohort retention and RFM segmentation in SQL with window functions, cross-checked the results in pandas, and used a two-proportion z-test to check whether late first orders reduce repeat purchases. I then stress-tested that result, because customers from earlier months had more time to come back."

**Result:** "97.8% of customers buy only once. Late orders get 2.3 stars instead of 4.3. A late first order also goes with fewer repeat purchases, but the gap shrank from 32% to 21% once I gave every customer the same follow-up time, so I called it suggestive and proposed an A/B test. I recommended a second-purchase campaign for high-value new customers, a win-back campaign, and a seller SLA scorecard, since 30% of sellers cause over half of the delays. I sized a 1-point improvement in repeat rate at about R$150k."

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
Not provably. This is observational data, so I can show an association, not causation, and the association is weaker than my first test suggested (see the next questions). It points the same way in all five versions of the test, but only the original one is statistically significant. To establish causation you'd run an experiment, for example proactive delay alerts for a random half of late orders.

**Q: Your first test gave p = 0.001. Why does the README now say p = 0.08?**
Same question, fairer comparison. The first test asked "did the customer ever buy again?". A customer from Jan-2017 had up to 20 months to come back, one from Feb-2018 only about 7, and late deliveries were clustered in the short-follow-up months (12% of first orders were late in Nov-2017 and 14% in Feb-2018, against 3–8% in the other months). On average the late group had 9.8 months to return and the on-time group 11.4. When I gave everyone the same 180 days, the gap fell from 0.94 to 0.42 percentage points (-32% to -21%) and p rose to 0.08. I kept both numbers in the repo so a reader can see what that one decision does.

**Q: Why 180 days?**
55% of repeat purchases happen within 90 days, so 180 days captures most repeat behaviour, and every customer in the Jan-2017 to Feb-2018 cohort has at least 180 days of data. It is a judgment call, so I also ran early cohorts only (Jan to Oct 2017), which pointed the same way.

**Q: What are the Mantel-Haenszel test and the logistic regression for?**
Both ask "is the gap still there when I compare like with like?" Mantel-Haenszel compares late and on-time customers inside each first-order month and pools the results, so the calendar effect cancels out. The logistic regression does the same and also controls for state and order value. Both gave an odds ratio of about 0.8 with a confidence interval that includes 1 (0.62–1.06 and 0.64–1.09).

**Q: So is there an effect or not?**
I can't say either way. The best estimate is about 0.4 percentage points lower, and the 95% interval runs from -0.85 points to zero. To detect a gap that small reliably (80% power) I would need about 15,900 late-first-order customers, and I have 3,667. So the honest wording is "suggestive", and the next step is an A/B test, not a bigger claim.

**Q: How did you check your SQL was correct?**
I re-computed the cohort table independently in pandas: the maximum difference was 0.005 percentage points (rounding). I also built a "check your numbers" table so the Power BI measures can be validated against the SQL totals.

**Q: What would you do with more time / data?**
A repurchase-propensity model to target the right customers; NLP on the Portuguese review comments to find *why* customers complain; a delivery-time prediction model to trigger delay alerts; and margin data to size impact in profit, not just revenue.

**Q: What would you do differently next time?**
Fix the outcome window before looking at any result (for example "repurchase within 180 days" instead of "ever"), and check that the groups I compare had the same follow-up time. I would also test a headline result from a few angles before putting it in the README.

**Q: Did you use AI tools to build this?**
Yes. I built it with Claude Code as my coding assistant. [Add what you personally decided or checked, only if it is true.] The project has its own safeguards: a pandas cross-check of the SQL results and a robustness test of the main finding. I can walk through any query and explain why it is written that way.

> Hinglish: yeh answer tabhi bolna jab tum sach mein har SQL file aur har decision samjha sako. Homework: har `sql/*.sql` file ek baar khud padho aur 2-3 line mein apne shabdon mein likho ki woh kya karti hai. Jo samajh na aaye woh Claude se poochho.

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

## Statistics concepts you can point to

| Concept | Where |
|---|---|
| Two-proportion z-test | `notebooks/olist_analysis.ipynb`, section 6 |
| Unequal follow-up time as a confounder | README "Robustness check", `scripts/robustness_check.py` |
| Fixed-window outcome ("bought again within 180 days") | `scripts/robustness_check.py`, variants B and C |
| Mantel-Haenszel stratified odds ratio | `scripts/robustness_check.py`, `mantel_haenszel()` |
| Logistic regression with controls (GLM Binomial) | `scripts/robustness_check.py`, `logistic()` |
| Power and sample size | `scripts/robustness_check.py`, `customers_needed()` |

## LinkedIn post (draft)

> 97.8% of customers on a Brazilian marketplace never ordered again. Here's what I found when I dug into 100K orders. 🧵
>
> I analyzed Olist's public e-commerce data (9 tables, 2016–2018) with SQL and Python:
> 📦 Late deliveries drop average reviews from 4.3★ to 2.3★
> 🔁 Customers whose first order arrived late had a 17–32% lower repeat rate, but the gap shrinks and loses statistical significance when every customer gets equal time to come back. Next step: an A/B test, not a bigger claim
> 💰 Repeat customers spend 2x more, so +1 point of repeat rate ≈ R$150K
> 🚚 30% of sellers cause 54% of late deliveries
>
> My recommendations: a second-purchase program in the first 90 days, proactive delay alerts, and a seller SLA scorecard.
>
> Full project (SQL, notebook, dashboard): [GitHub link]
> #DataAnalytics #SQL #Python #Statistics
