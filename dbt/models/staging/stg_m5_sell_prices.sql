-- Staging view for M5 weekly sell prices. One row per store × item × fiscal week.
-- Materialises to STAGING.STG_M5_SELL_PRICES.

SELECT
    store_id,
    item_id,
    wm_yr_wk,
    sell_price
FROM {{ source('m5', 'SELL_PRICES') }}
