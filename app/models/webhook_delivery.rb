class WebhookDelivery < ApplicationRecord
  belongs_to :webhook_endpoint

  scope :recent, -> { order(created_at: :desc) }

  def success? = response_code.present? && response_code.between?(200, 299)
end
