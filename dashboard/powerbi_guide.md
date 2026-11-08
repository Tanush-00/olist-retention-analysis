# Power BI dashboard: build guide

A `.pbix` file can only be created inside Power BI Desktop, so this guide walks you through building it from the clean tables the pipeline exports. Expect **1.5–2 hours**. That time is worth it: interviewers often ask *"how did you build your model and measures?"*

The finished report mirrors the HTML dashboard (`dashboard/olist_dashboard.html`), so use that as your visual reference.

---

## 1. Load the data

1. Run `python run_pipeline.py` (or at least `scripts/export_powerbi.py`) so that `data/processed/` exists.
2. Power BI Desktop → **Get data → Text/CSV**. Load all 7 files from `data/processed/`:

| File | Grain | Rows |
|---|---|---|
| `fact_orders.csv` | one row per valid order | 98,207 |
| `fact_order_items.csv` | one row per item sold | 112,101 |
| `dim_customers.csv` | one row per real customer (with RFM segment) | 94,990 |
| `dim_products.csv` | one row per product | 32,951 |
| `dim_sellers.csv` | one row per seller | 3,095 |
| `dim_date.csv` | one row per calendar day | 791 |
| `cohort_retention.csv` | cohort month × months since first purchase | 182 |

3. In **Power Query** (Transform data), check the column types:
   - `purchase_date`, `delivered_date`, `estimated_date`, `first_purchase_date`, `last_purchase_date`, `dim_date[date]` → **Date**
   - `order_value`, `product_value`, `freight_value`, `price`, `total_spend`, `delivery_days`, `retention_pct` → **Decimal number**
   - `is_late`, `is_delivered`, `is_repeat_customer`, `review_score`, `delay_days`, `month_number` → **Whole number**
   - `customer_unique_id`, `order_id`, `product_id`, `seller_id`, `purchase_month`, `cohort_month`, `year_month` → **Text**

> If your Windows region uses a comma as the decimal separator, set *File → Options → Regional settings → Locale for import* to **English (United States)**.

## 2. Build the model (star schema)

Model view → create these relationships (all **one-to-many, single direction**):

| From (one side) | To (many side) |
|---|---|
| `dim_date[date]` | `fact_orders[purchase_date]` |
| `dim_customers[customer_unique_id]` | `fact_orders[customer_unique_id]` |
| `fact_orders[order_id]` | `fact_order_items[order_id]` |
| `dim_products[product_id]` | `fact_order_items[product_id]` |
| `dim_sellers[seller_id]` | `fact_order_items[seller_id]` |

Then:
- Select `dim_date` → **Mark as date table** → column `date`.
- Sort `dim_date[month_name]` by `month_number`, and `weekday_name` by `weekday_number`.
- Hide the ID columns on the fact tables (right-click → Hide in report view).
- Leave `cohort_retention` unrelated. It is a pre-aggregated table for the heatmap.

```
              dim_date          dim_customers
                  \                 /
                   \               /
                   fact_orders ---------- fact_order_items
                                            /          \
                                     dim_products   dim_sellers
```

## 3. DAX measures

Create an empty table to hold them: *Home → Enter data → name it `_Measures`*. Then add:

```DAX
Revenue = SUM ( fact_orders[order_value] )

Orders = COUNTROWS ( fact_orders )

Customers = DISTINCTCOUNT ( fact_orders[customer_unique_id] )

AOV = DIVIDE ( [Revenue], [Orders] )

Avg Review = AVERAGE ( fact_orders[review_score] )

Delivered Orders = CALCULATE ( [Orders], fact_orders[is_delivered] = 1 )

Late Orders = CALCULATE ( [Orders], fact_orders[is_late] = 1 )

Late % = DIVIDE ( [Late Orders], [Delivered Orders] )

Avg Delivery Days =
    CALCULATE ( AVERAGE ( fact_orders[delivery_days] ), fact_orders[is_delivered] = 1 )

Negative Review % =
    DIVIDE (
        CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[review_score] <= 2 ),
        CALCULATE ( COUNTROWS ( fact_orders ), NOT ISBLANK ( fact_orders[review_score] ) )
    )

Avg Review (Late) = CALCULATE ( [Avg Review], fact_orders[is_late] = 1 )

Avg Review (On Time) = CALCULATE ( [Avg Review], fact_orders[is_late] = 0 )

Repeat Customers =
    CALCULATE ( COUNTROWS ( dim_customers ), dim_customers[is_repeat_customer] = 1 )

Repeat Rate % = DIVIDE ( [Repeat Customers], COUNTROWS ( dim_customers ) )

Revenue PM = CALCULATE ( [Revenue], DATEADD ( dim_date[date], -1, MONTH ) )

Revenue MoM % = DIVIDE ( [Revenue] - [Revenue PM], [Revenue PM] )

Revenue LY = CALCULATE ( [Revenue], SAMEPERIODLASTYEAR ( dim_date[date] ) )

Revenue YoY % = DIVIDE ( [Revenue] - [Revenue LY], [Revenue LY] )

Item Revenue = SUM ( fact_order_items[price] )

Segment Customers % =
    DIVIDE ( COUNTROWS ( dim_customers ),
             CALCULATE ( COUNTROWS ( dim_customers ), ALL ( dim_customers[segment] ) ) )

Segment Revenue % =
    DIVIDE ( SUM ( dim_customers[total_spend] ),
             CALCULATE ( SUM ( dim_customers[total_spend] ), ALL ( dim_customers[segment] ) ) )

Retention % = DIVIDE ( SUM ( cohort_retention[active_customers] ),
                       SUM ( cohort_retention[cohort_customers] ) )

Seller Late % =
    DIVIDE (
        CALCULATE ( DISTINCTCOUNT ( fact_order_items[order_id] ), fact_order_items[is_late] = 1 ),
        CALCULATE ( DISTINCTCOUNT ( fact_order_items[order_id] ), NOT ISBLANK ( fact_order_items[is_late] ) )
    )
```

Format `Late %`, `Repeat Rate %`, `Negative Review %`, `Revenue MoM %`, `Revenue YoY %`, `Segment … %` and `Retention %` as **Percentage**. Format `Revenue`, `AOV` and `Item Revenue` as **Currency R$**.

### Check your numbers

Before building visuals, put these measures in cards **with no filters**. They must match the SQL/Python results:

| Measure | Expected |
|---|---|
| Revenue | R$15,735,527 |
| Orders | 98,207 |
| Customers | 94,990 |
| AOV | R$160.24 |
| Avg Review | 4.12 |
| Late % | 6.77% |
| Avg Review (Late) / (On Time) | 2.27 / 4.29 |
| Repeat Rate % | 2.17% |

If one doesn't match, check the column types and relationships first.

## 4. Report pages

**Theme:** *View → Themes → Customize current theme*. Set the first data color to `#2a78d6` (blue) and the second to `#eb6834` (orange). Use `#c3c2b7` (gray) for "everything else" bars. Keep the background white and gridlines light.

Add one **slicer row** at the top of each page (`dim_date[year]`, `fact_orders[customer_state]`). Filter trend visuals to `year_month` 2017-01 … 2018-08, because the first and last months are incomplete.

### Page 1: Executive Overview
- Cards: Revenue · Orders · Customers · AOV · Avg Review · Revenue YoY %
- Line chart: `dim_date[year_month]` × Revenue
- Bar chart: `fact_orders[customer_state]` × Revenue (Top N = 10)
- Bar chart: `fact_orders[payment_type]` × Orders (show as % of grand total)

### Page 2: Customers & Retention
- Cards: Repeat Rate % · Customers · one-time share (`1 - [Repeat Rate %]`)
- **Matrix heatmap:** rows `cohort_retention[cohort_month]`, columns `month_number` (filter 1–12), values `Retention %`. Use *Conditional formatting → Background color → Gradient* from white to `#0d366b`.
- Clustered bar: `dim_customers[segment]` × `Segment Customers %` and `Segment Revenue %`
- Table: segment, customers, avg `total_spend`, avg `recency_days`

### Page 3: Delivery & Reviews
- Cards: Late % · Avg Delivery Days · Avg Review (Late) · Avg Review (On Time) · Negative Review %
- Column chart: `fact_orders[delay_bucket]` × Avg Review (color the late buckets red with *Conditional formatting → Rules*)
- Line chart: `year_month` × Late %
- Line chart: `year_month` × Avg Review (a separate chart; never put two y-axes on one chart)
- Bar chart: `customer_state` × Late % (sorted descending), with a constant line at 6.8%

### Page 4: Sellers & Categories
- Bar chart: `dim_products[category]` × Item Revenue (Top N = 10)
- Table: `dim_sellers[seller_id]`, `seller_state`, Orders, Seller Late %, Avg Review. Filter to sellers with 100+ orders and sort by Seller Late %.
- Table: `dim_products[category]` × Avg Review, Negative Review %, Late %

### Finishing touches
- Add a text box on each page with the 2–3 key insights (copy them from the README).
- *Format → Tooltips*: add Orders and Avg Review to the bar-chart tooltips.
- Save as `dashboard/olist_dashboard.pbix`. Then *File → Export → PDF* and take PNG screenshots for the README and LinkedIn.
