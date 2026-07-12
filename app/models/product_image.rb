class ProductImage < ApplicationRecord
  belongs_to :product
  validates :remote_url, presence: true
end
