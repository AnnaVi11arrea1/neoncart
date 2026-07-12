class WebhookEndpoint < ApplicationRecord
  EVENTS = %w[order.paid order.status_changed order.shipped product.updated].freeze

  has_many :deliveries, class_name: "WebhookDelivery", dependent: :destroy

  validates :name, :url, presence: true
  validates :url, format: { with: %r{\Ahttps?://}i }

  before_validation { self.secret ||= SecureRandom.hex(32) }

  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { active.where("? = ANY(events)", event) }
end
