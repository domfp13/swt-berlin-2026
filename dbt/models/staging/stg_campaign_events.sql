with source as (
    select * from {{ source('raw', 'campaign_events') }}
)

select
    event_id,
    campaign_id,
    customer_id,
    event_type,
    convert_timezone('UTC', event_timestamp)::timestamp_ntz as event_timestamp,
    device_type
from source
