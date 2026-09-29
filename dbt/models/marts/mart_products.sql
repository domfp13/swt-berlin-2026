with products as (
    select * from {{ ref('stg_products') }}
),

categories as (
    select * from {{ ref('stg_product_categories') }}
)

select
    p.product_id,
    p.product_name,
    p.category_id,
    c.category_name,
    c.margin_tier,
    p.list_price,
    p.cost_price,
    p.list_price - p.cost_price as margin_amount,
    p.is_negative_margin,
    p.created_date,
    p.is_active
from products p
left join categories c on c.category_id = p.category_id
