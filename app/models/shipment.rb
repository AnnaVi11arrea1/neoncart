class Shipment < ApplicationRecord
  belongs_to :order
  belongs_to :supplier, optional: true

  before_save :ensure_tracking_url
  validate :tracking_info_present

  def display_carrier = carrier.presence || "Carrier"

  private

  # A carrier tracking number generates its own link (see Tracking::LinkBuilder),
  # but plenty of overseas/manual-mode suppliers don't give a real trackable
  # number at all — just a status-page link the admin found. Either one is
  # enough to notify the customer with; only reject a shipment with neither.
  def ensure_tracking_url
    self.tracking_url = Tracking::LinkBuilder.url_for(carrier, tracking_number) if tracking_url.blank? && tracking_number.present?
  end

  def tracking_info_present
    errors.add(:base, "Add a tracking number or a link the customer can follow") if tracking_number.blank? && tracking_url.blank?
  end
end
