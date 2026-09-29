{{ config(severity='warn') }}

-- Quality note (RAW_ORDERS): 1,203 orders are dated before the customer's SIGNUP_DATE.
select o.order_id, o.order_date, c.signup_date
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c on c.customer_id = o.customer_id
where o.order_date < c.signup_date
