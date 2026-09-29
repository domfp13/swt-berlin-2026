with payments as (
    select * from {{ ref('stg_payments') }}
),

orders as (
    select order_id, customer_id from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    p.payment_id,
    p.order_id,
    p.payment_seq,
    p.payment_method,
    p.payment_amount,
    p.payment_date,
    p.payment_status,
    p.is_successful,
    o.customer_id,
    c.customer_name,
    c.region,
    c.segment
from payments p
left join orders o on o.order_id = p.order_id
left join customers c on c.customer_id = o.customer_id
