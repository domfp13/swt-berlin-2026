with refunds as (
    select * from {{ ref('stg_refunds') }}
),

orders as (
    select order_id, customer_id from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    r.refund_id,
    r.order_id,
    r.refund_date,
    r.refund_amount,
    o.customer_id,
    c.customer_name,
    c.region,
    c.segment
from refunds r
left join orders o on o.order_id = r.order_id
left join customers c on c.customer_id = o.customer_id
