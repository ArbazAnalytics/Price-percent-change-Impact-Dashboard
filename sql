1) Weekly Aggregation + Log Prep (Reusable View)

Why: Elasticity is estimated on weekly data to reduce daily noise.
We compute weekly average price and total quantity, plus log transforms for the regression.
We keep both a precise (unrounded) avg_price_raw for logs and a pretty avg_price for display.



CREATE OR REPLACE VIEW weekly_demand_logs AS
WITH weekly AS (
  SELECT
      MENU_ITEM,
      DATE_TRUNC('week', BUSINESS_DAY)          AS WEEK_START,
      AVG(NET_UNIT_PRICE)                       AS AVG_PRICE_RAW,   -- use for logs (avoid rounding bias)
      ROUND(AVG(NET_UNIT_PRICE), 2)             AS AVG_PRICE,       -- readable
      SUM(QUANTITY)                             AS TOTAL_QUANTITY
  FROM POS_DATA
  GROUP BY MENU_ITEM, DATE_TRUNC('week', BUSINESS_DAY)
)
SELECT
    MENU_ITEM,
    WEEK_START,
    AVG_PRICE,
    TOTAL_QUANTITY,
    LN(AVG_PRICE_RAW)  AS LN_PRICE,
    LN(TOTAL_QUANTITY) AS LN_QUANTITY
FROM weekly
WHERE AVG_PRICE_RAW    > 0
  AND TOTAL_QUANTITY   > 0
ORDER BY MENU_ITEM, WEEK_START;


Key points

DATE_TRUNC('week', ...) gives a consistent weekly key for grouping.

Logs turn % changes into a straight-line relation (slope = elasticity).


2) Elasticity per Item (slope) + Fit (R²)

Why: In a log–log demand model
  
ln(Q)=α+β⋅ln(P)+ε

the slope β is price elasticity. R² shows how well price explains demand.

-- Per-item elasticity and diagnostics
CREATE OR REPLACE VIEW item_elasticity AS
SELECT
    MENU_ITEM,
    REGR_SLOPE(LN_QUANTITY, LN_PRICE) AS ELASTICITY,  -- β (price elasticity)
    REGR_R2  (LN_QUANTITY, LN_PRICE)  AS R_SQUARED,   -- model fit (0..1)
    COUNT(*)                           AS WEEKS_USED   -- sample size
FROM weekly_demand_logs
GROUP BY MENU_ITEM
ORDER BY MENU_ITEM;


Reading results

Elasticity (β): negative is expected (price ↑ → quantity ↓).

|β| > 1 → elastic (demand very price-sensitive)

|β| < 1 → inelastic

R²: closer to 1 = better fit. Low R² means price doesn’t explain much.



3) Keep Only Usable Results (Filter)

Why: We want items where the model has at least some explanatory power and enough data points.


-- Tweak thresholds as needed (R² >= 0.10 is a pragmatic starting point in POS data)
WITH per_item AS (
  SELECT
      MENU_ITEM,
      REGR_SLOPE(LN_QUANTITY, LN_PRICE) AS ELASTICITY,
      REGR_R2  (LN_QUANTITY, LN_PRICE)  AS R_SQUARED,
      COUNT(*)                           AS WEEKS_USED
  FROM weekly_demand_logs
  GROUP BY MENU_ITEM
)
SELECT *
FROM per_item
WHERE R_SQUARED >= 0.10
  AND ELASTICITY < 0          -- keep economically sensible sign
  AND WEEKS_USED >= 15        -- ensure reasonable sample
ORDER BY R_SQUARED DESC;

