with source as (
    select * from {{ source('raw', 'customers') }}
)

select
    customer_id,
    customer_name,
    region,
    segment,
    signup_date
from source
