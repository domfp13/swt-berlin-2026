{{ config(severity='warn') }}

-- Quality note (RAW_SHIPMENTS): DELIVERED_DATE in the future (looks like an estimate).
select shipment_id, order_id, delivered_date
from {{ ref('stg_shipments') }}
where is_delivery_in_future
