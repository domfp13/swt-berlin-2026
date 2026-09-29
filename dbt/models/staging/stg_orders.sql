with source as (
    select * from {{ source('raw', 'orders') }}
)

select
    order_id,
    customer_id,
    order_date,
    status as order_status,
    amount as order_amount,
    coalesce(status = 'COMPLETED', false) as is_completed
from source
