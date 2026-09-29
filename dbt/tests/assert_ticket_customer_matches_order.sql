{{ config(severity='warn') }}

-- Quality note (RAW_SUPPORT_TICKETS): CUSTOMER_ID differs from the order's CUSTOMER_ID.
select t.ticket_id, t.customer_id as ticket_customer_id, o.customer_id as order_customer_id
from {{ ref('stg_support_tickets') }} t
join {{ ref('stg_orders') }} o on o.order_id = t.order_id
where t.customer_id <> o.customer_id
