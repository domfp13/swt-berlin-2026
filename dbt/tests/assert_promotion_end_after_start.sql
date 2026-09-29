{{ config(severity='warn') }}

-- Quality note (RAW_PROMOTIONS): END_DATE before START_DATE.
select promotion_id, start_date, end_date
from {{ ref('stg_promotions') }}
where is_end_before_start
