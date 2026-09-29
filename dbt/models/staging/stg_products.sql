with source as (
    select * from {{ source('raw', 'products') }}
)

select
    product_id,
    product_name,
    category_id,
    list_price,
    cost_price,
    created_date,
    is_active,
    coalesce(cost_price > list_price, false) as is_negative_margin
from source
