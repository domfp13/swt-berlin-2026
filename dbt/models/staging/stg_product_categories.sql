with source as (
    select * from {{ source('raw', 'product_categories') }}
)

select
    category_id,
    category_name,
    margin_tier
from source
