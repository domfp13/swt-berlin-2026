{{ config(severity='warn') }}

-- Quality note (RAW_ORDERS / RAW_PAYMENTS): successful payments do not sum to the order amount.
with paid as (
    select order_id, sum(iff(is_successful, payment_amount, 0)) as paid_amount
    from {{ ref('stg_payments') }}
    group by order_id
)

select o.order_id, o.order_status, o.order_amount, coalesce(p.paid_amount, 0) as paid_amount
from {{ ref('stg_orders') }} o
left join paid p on p.order_id = o.order_id
where o.is_completed
  and abs(o.order_amount - coalesce(p.paid_amount, 0)) > 0.01
