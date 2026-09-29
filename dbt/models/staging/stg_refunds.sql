with source as (
    select * from {{ source('raw', 'refunds') }}
)

select
    refund_id,
    order_id,
    refund_date,
    refund_amount
from source
