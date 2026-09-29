with orders as (
    select * from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.order_amount,
    o.is_completed,
    c.customer_name,
    c.region,
    c.segment
from orders o
left join customers c on c.customer_id = o.customer_id
