class Variant < ApplicationRecord
  belongs_to :product

  validates :title, presence: true

  scope :available, -> { where(available: true) }

  def price_cents_or_default = price_cents.presence || product.price_cents

  def label
    options.present? ? options.values.join(" / ") : title
  end
end
