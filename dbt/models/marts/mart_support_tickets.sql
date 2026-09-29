with tickets as (
    select * from {{ ref('stg_support_tickets') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    t.ticket_id,
    t.customer_id,
    t.order_id,
    t.category,
    t.priority,
    t.ticket_status,
    t.created_at,
    t.resolved_at,
    t.satisfaction_score,
    t.is_resolved_before_created,
    t.is_resolved_in_future,
    t.is_status_resolution_mismatch,
    iff(t.is_resolved_before_created or t.is_resolved_in_future, null, datediff(hour, t.created_at, t.resolved_at)) as resolution_hours,
    c.customer_name,
    c.region,
    c.segment
from tickets t
left join customers c on c.customer_id = t.customer_id
