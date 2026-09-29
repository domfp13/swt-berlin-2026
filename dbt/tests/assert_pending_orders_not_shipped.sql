{{ config(severity='warn') }}

-- Quality note (RAW_SHIPMENTS / RAW_ORDERS): PENDING orders that already have a shipment.
select o.order_id, o.order_status, s.shipment_id, s.delivered_date
from {{ ref('stg_orders') }} o
join {{ ref('stg_shipments') }} s on s.order_id = o.order_id
where o.order_status = 'PENDING'
