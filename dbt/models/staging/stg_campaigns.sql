with source as (
    select * from {{ source('raw', 'campaigns') }}
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
    coalesce(end_date < start_date, false) as is_end_before_start,
    coalesce(spend > budget, false) as is_over_budget
from source
