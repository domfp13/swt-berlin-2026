with campaigns as (
    select * from {{ ref('stg_campaigns') }}
)

select
    campaign_id,
    campaign_name,
    channel,
    budget,
    spend,
    start_date,
    end_date,
    target_region,
    is_end_before_start,
    is_over_budget
from campaigns
