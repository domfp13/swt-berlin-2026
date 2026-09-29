with source as (
    select * from {{ source('raw', 'shipments') }}
)

select
    shipment_id,
    order_id,
    shipped_date,
    delivered_date,
    shipping_method,
    carrier,
    shipping_cost,
    coalesce(delivered_date > convert_timezone('UTC', current_timestamp())::date, false) as is_delivery_in_future
from source
