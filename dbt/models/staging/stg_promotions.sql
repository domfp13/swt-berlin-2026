with source as (
    select * from {{ source('raw', 'promotions') }}
)

select
    promotion_id,
    promo_code,
    discount_type,
    discount_value,
    start_date,
    end_date,
    min_order_amount,
    coalesce(end_date < start_date, false) as is_end_before_start
from source
