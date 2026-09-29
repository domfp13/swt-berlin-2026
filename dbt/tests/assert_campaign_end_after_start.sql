{{ config(severity='warn') }}

-- Quality note (RAW_CAMPAIGNS): END_DATE before START_DATE.
select campaign_id, start_date, end_date
from {{ ref('stg_campaigns') }}
where is_end_before_start
