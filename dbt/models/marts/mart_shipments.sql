with shipments as (
    select * from {{ ref('stg_shipments') }}
),

orders as (
    select order_id, customer_id from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    s.shipment_id,
    s.order_id,
    s.shipped_date,
    s.delivered_date,
    s.shipping_method,
    s.carrier,
    s.shipping_cost,
    s.is_delivery_in_future,
    iff(s.is_delivery_in_future, null, datediff(day, s.shipped_date, s.delivered_date)) as delivery_days,
    o.customer_id,
    c.customer_name,
    c.region,
    c.segment
from shipments s
left join orders o on o.order_id = s.order_id
left join customers c on c.customer_id = o.customer_id
