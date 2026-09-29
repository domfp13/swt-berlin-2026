with events as (
    select * from {{ ref('stg_campaign_events') }}
),

campaigns as (
    select * from {{ ref('stg_campaigns') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    e.event_id,
    e.campaign_id,
    e.customer_id,
    e.event_type,
    e.event_timestamp,
    e.device_type,
    ca.campaign_name,
    ca.channel,
    ca.target_region,
    cu.customer_name,
    cu.region,
    cu.segment
from events e
left join campaigns ca on ca.campaign_id = e.campaign_id
left join customers cu on cu.customer_id = e.customer_id
