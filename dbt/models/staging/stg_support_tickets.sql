with source as (
    select * from {{ source('raw', 'support_tickets') }}
)

select
    ticket_id,
    customer_id,
    order_id,
    category,
    priority,
    status as ticket_status,
    created_at::timestamp_ntz as created_at,
    resolved_at,
    satisfaction_score,
    coalesce(resolved_at < created_at::timestamp_ntz, false) as is_resolved_before_created,
    coalesce(resolved_at > convert_timezone('UTC', current_timestamp())::timestamp_ntz, false) as is_resolved_in_future,
    coalesce(
        (status in ('Closed', 'Resolved') and resolved_at is null)
        or (status in ('Open', 'In Progress') and resolved_at is not null),
        false
    ) as is_status_resolution_mismatch
from source
