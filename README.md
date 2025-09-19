# Price Elasticity Project — From Raw POS to What-If Decisions

## 1) Why we did this

Prices move revenue and profit, but not every item reacts the same way. The goal was to measure how sensitive each menu item’s demand is to price (elasticity) and then simulate revenue if prices go up or down (e.g., ±10%). This turns raw POS data into a simple      “what if I change price by X%?” decision.

## 2) Data we started with

POS_DATA (CSV → Snowflake) containing:

business_day, menu_item, quantity

unit_price, discount (used to derive net price before tax)

other context like daypart, service_mode, store_id (kept for later cuts)

We used net_unit_price (actual paid price per unit, before tax) because elasticity must reflect what guests actually paid, not list price.

## 3) How the Snowflake part works (the backbone)
### a) Weekly rollup (reduce noise, capture price movement)

We aggregated to item × week so both price and quantity vary meaningfully.
From POS_DATA we created weekly_deman_logs with:

week_start

avg_price (rounded)

total_quantity

weekly_revenue

log transforms for regression: ln(avg_price_raw) and ln(total_quantity)

Why weekly? Transaction-level is noisy (weather, one-off orders). Weekly smooths noise and keeps the price–demand signal.

### b) Elasticity by item (log–log regression)

Using Snowflake’s regression functions on the weekly table:

REGR_SLOPE(In_quantity, In_price) → Elasticity

REGR_R2(In_quantity, In_price) → Fit quality (R²)

We also computed supporting stats per item:

weeks_used

avg_weekly_qty

avg_weekly_revenue

qty_weighted_price as baseline_price

first_week, last_week

### c) Keep only reliable items for simulation

We filtered to items where:

r_squared > 0.10 (some explanatory power)

elasticity < 0 (downward-sloping demand)

This produces elasticity_summary — the clean input for Sigma.

You’ll find all the SQL in the repo. The final query block selects the filtered elasticity set ordered by R² (highest first).

## 4) What the numbers mean (quick read)

Elasticity (slope): % change in quantity for a 1% change in price (usually negative).

Example: -1.3 → a 1% price increase reduces demand by ~1.3%.

R²: how well price explains quantity in the weekly data. Not perfect, but a useful guide.

## 5) Sigma: turning the model into decisions

We built a Price Change Impact dashboard on top of elasticity_summary:

### A) Inputs and baseline

From SQL we brought:

elasticity, r_squared, avg_weekly_qty, avg_weekly_revenue, baseline_price, weeks_used

### B) What-if controls

A slider for Price Change % (e.g., −20% to +20%).

### C) Core calculations in Sigma
Demand Change % = [Elasticity] * [Price Change %]
New Quantity     = [avg_weekly_qty]    * (1 + [Demand Change %])
New Price        = [baseline_price]    * (1 + [Price Change %])
New Revenue      = [New Quantity]      * [New Price]
Revenue Delta    = [New Revenue]       - [avg_weekly_revenue]

### D) Visuals and tables

KPI tiles: Average weekly revenue (baseline) vs New weekly revenue; Relative change; Revenue delta.

Bars: Baseline vs New revenue by item.

Gain/Loss bars: Revenue Delta by item.

Detail table: item, elasticity, R², weeks_used, baseline price/qty, new price/qty, new revenue, delta.

## 6) What the scenarios show (the screenshots)

### a) Scenario A — Price −10%

![image](https://github.com/ArbazAnalytics/Price-percent-change-Impact-Dashboard/blob/1840e1c5cbc1017c3a61aec12dd53e161996d791/price_down_by_10%25.jpg)
New Weekly Revenue: 150.71 vs Baseline 109.84

Revenue Delta: +40.87 (+37.2%)

Elastic items (e.g., Chicken Sandwich, Cheeseburger) gain revenue when prices are reduced, because the increase in quantity outweighs the lower price.

### b) Scenario B — Price +10%

![image](https://github.com/ArbazAnalytics/Price-percent-change-Impact-Dashboard/blob/1840e1c5cbc1017c3a61aec12dd53e161996d791/price_up_by_10%25.jpg)

New Weekly Revenue: 57.44 vs Baseline 109.84

Revenue Delta: −52.40 (−47.7%)

Elastic items lose revenue when prices are raised. The drop in quantity is greater than the gain from higher prices.

## 7) What we learned (the “so what”)

Items differ: some are safe for small increases (inelastic), others respond better to promos (elastic).

A single global price move is blunt. Targeted changes by item drive better outcomes.

Even modest R² can be useful when combined with guardrails (filters, weeks_used).

## 8) How this connects end-to-end

Upload POS CSV to Snowflake.

SQL builds weekly features and runs log–log regressions to get elasticity and R².

Filter to credible items and publish elasticity_summary.

Sigma reads that view, applies a Price Change % slider, and calculates new price, new quantity, and new revenue live.

Result: a working what-if tool that ties statistical estimates to revenue impact, item by item.

## 9) What’s next (nice, simple upgrades)

Per-store elasticities (store × item) to respect local behavior.

Confidence bands (probabilistic view) using standard errors or Monte Carlo in Python/Streamlit, then surface ranges in Sigma.

Controls for promos/dayparts to see elasticity “by context”.

## 10) TL;DR

We measured how each item reacts to price (elasticity) using weekly Snowflake regressions, then simulated new revenue in Sigma with a simple slider. The outcome is a clear, practical dashboard that answers:
“If I change price by X%, what happens to quantity and revenue for each item?”
