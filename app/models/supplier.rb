class Supplier < ApplicationRecord
  has_many :products, dependent: :nullify
  has_many :order_items, dependent: :nullify

  encrypts :api_key, :api_secret if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?

  validates :name, :adapter, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :fulfillment_mode, inclusion: { in: %w[auto manual] }

  before_validation { self.slug = name.to_s.parameterize if slug.blank? }

  scope :active, -> { where(active: true) }

  def adapter_instance
    adapter.constantize.new(self)
  end

  def auto? = fulfillment_mode == "auto"
  def manual? = fulfillment_mode == "manual"

  def credentials_present?
    api_key.present? || settings["auth_token"].present?
  end
end
