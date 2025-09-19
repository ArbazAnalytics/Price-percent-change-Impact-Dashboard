01_weekly_demand_logs.sql

02_elasticity_summary.sql

03_filter_valid_items.sql


1. Create Weekly Demand Logs
CREATE OR REPLACE VIEW weekly_deman_logs AS
WITH weekly AS (
  SELECT
      Menu_item,
      DATE_TRUNC('week', Business_Day) AS week_start,
      AVG(net_unit_price)               AS avg_price_raw,
      ROUND(AVG(net_unit_price), 2)     AS avg_price,
      SUM(quantity)                     AS total_quantity,
      SUM(net_unit_price * quantity)    AS weekly_revenue
  FROM POS_DATA
  WHERE net_unit_price > 0 AND quantity > 0
  GROUP BY Menu_item, DATE_TRUNC('week', Business_Day)
)
SELECT
    Menu_item,
    week_start,
    avg_price,
    total_quantity,
    weekly_revenue,
    LN(avg_price_raw)   AS In_price,
    LN(total_quantity)  AS In_quantity
FROM weekly
WHERE avg_price_raw > 0
  AND total_quantity > 0
ORDER BY menu_item, week_start;


Why?

Groups sales into weekly buckets so demand/price trends are comparable over time.

Uses log-transforms (LN) for price and quantity → this allows a log-log regression which directly estimates elasticity (slope = %ΔQ / %ΔP).

Filters out invalid data (price/quantity > 0).

2. Create Elasticity Summary
CREATE OR REPLACE VIEW elasticity_summary AS
WITH item_stats AS (
  SELECT
      Menu_item,
      COUNT(*)                                        AS weeks_used,
      AVG(total_quantity)                             AS avg_weekly_qty,
      AVG(weekly_revenue)                             AS avg_weekly_revenue,
      SUM(weekly_revenue) / NULLIF(SUM(total_quantity), 0) AS qty_weighted_price,
      MIN(week_start)                                 AS first_week,
      MAX(week_start)                                 AS last_week
  FROM weekly_deman_logs
  GROUP BY Menu_item
),
elasticity_results AS (
  SELECT
      Menu_item,
      REGR_SLOPE(In_quantity, In_price) AS elasticity,
      REGR_R2(In_quantity, In_price)    AS r_squared
  FROM weekly_deman_logs
  GROUP BY Menu_item
)
SELECT
    e.Menu_item,
    e.elasticity,
    e.r_squared,
    s.weeks_used,
    s.avg_weekly_qty,
    s.qty_weighted_price   AS baseline_price,
    s.avg_weekly_revenue,
    s.first_week,
    s.last_week
FROM elasticity_results e
JOIN item_stats s USING (Menu_item);


Why?

Joins regression outputs (elasticity + R²) with item-level stats.

qty_weighted_price → better estimate of baseline price since it weights by sales volume.

Provides time span (first_week, last_week) so users know coverage.

3. Filter Valid Results
SELECT
    *
FROM elasticity_summary
WHERE r_squared > 0.10
  AND elasticity < 0
ORDER BY r_squared DESC;


Why?

r_squared > 0.10 → keeps only reasonably fitted models.

elasticity < 0 → ensures we only keep normal products (higher price → lower demand).

Sorting by R² highlights the most reliable elasticity estimates.
