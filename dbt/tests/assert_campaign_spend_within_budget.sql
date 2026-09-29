{{ config(severity='warn') }}

-- Quality note (RAW_CAMPAIGNS): SPEND greater than BUDGET.
select campaign_id, budget, spend
from {{ ref('stg_campaigns') }}
where is_over_budget
