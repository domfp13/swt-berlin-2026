{{ config(severity='warn') }}

-- Quality note (RAW_PRODUCTS): COST_PRICE greater than LIST_PRICE.
select product_id, list_price, cost_price
from {{ ref('stg_products') }}
where is_negative_margin
