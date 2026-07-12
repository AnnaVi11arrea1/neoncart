class Shipment < ApplicationRecord
  belongs_to :order
  belongs_to :supplier, optional: true

  before_save :ensure_tracking_url

  def display_carrier = carrier.presence || "Carrier"

  private

  def ensure_tracking_url
    self.tracking_url = Tracking::LinkBuilder.url_for(carrier, tracking_number) if tracking_url.blank? && tracking_number.present?
  end
end
