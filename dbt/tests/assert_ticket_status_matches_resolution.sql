{{ config(severity='warn') }}

-- Quality note (RAW_SUPPORT_TICKETS): status and RESOLVED_AT disagree.
select ticket_id, ticket_status, resolved_at
from {{ ref('stg_support_tickets') }}
where is_status_resolution_mismatch
