class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :variant, optional: true
  belongs_to :supplier, optional: true
  has_one :review, dependent: :destroy

  FULFILLMENT_STATUSES = %w[unfulfilled submitted awaiting_manual fulfilled cancelled].freeze
  validates :fulfillment_status, inclusion: { in: FULFILLMENT_STATUSES }

  scope :awaiting_manual, -> { where(fulfillment_status: "awaiting_manual") }

  def line_total_cents = unit_price_cents * quantity
end
