{{ config(severity='warn') }}

-- Quality note (RAW_CAMPAIGN_EVENTS): events outside their campaign's START_DATE-END_DATE window.
select e.event_id, e.campaign_id, e.event_timestamp, c.start_date, c.end_date
from {{ ref('stg_campaign_events') }} e
join {{ ref('stg_campaigns') }} c on c.campaign_id = e.campaign_id
where e.event_timestamp::date not between c.start_date and c.end_date
