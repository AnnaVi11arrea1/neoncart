class ProductImage < ApplicationRecord
  # touch: the storefront grids are fragment-cached on the product's
  # updated_at, so a new or replaced image has to move it.
  belongs_to :product, touch: true
  validates :remote_url, presence: true
end
