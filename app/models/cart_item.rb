class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product
  belongs_to :variant, optional: true

  validates :quantity, numericality: { greater_than: 0, less_than: 100 }

  def unit_price_cents = product.display_price_cents(variant)
  def line_total_cents = unit_price_cents * quantity
  def display_title
    variant ? "#{product.title} — #{variant.label}" : product.title
  end
end
