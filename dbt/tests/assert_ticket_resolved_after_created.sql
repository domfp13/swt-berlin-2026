{{ config(severity='warn') }}

-- Quality note (RAW_SUPPORT_TICKETS): RESOLVED_AT before CREATED_AT.
select ticket_id, created_at, resolved_at
from {{ ref('stg_support_tickets') }}
where is_resolved_before_created
