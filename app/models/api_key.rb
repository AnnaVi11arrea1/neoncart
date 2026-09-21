class ApiKey < ApplicationRecord
  # A scope not listed here is silently dropped by `generate!` below, because
  # it intersects against this list — so a key would be created looking fine
  # and every request with it would 403. Add the scope here first.
  SCOPES = %w[products:read orders:read orders:write orders:write_paid posts:write].freeze

  has_many :orders, dependent: :nullify

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  # Returns [record, raw_token] — raw token is only visible at creation time.
  def self.generate!(name:, scopes: %w[products:read orders:write], partner_url: nil)
    raw = "nc_live_#{SecureRandom.hex(24)}"
    record = create!(
      name:,
      scopes: scopes & SCOPES,
      partner_url:,
      prefix: raw.first(12),
      token_digest: digest(raw)
    )
    [record, raw]
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    active.find_by(token_digest: digest(raw_token))&.tap { |k| k.update_column(:last_used_at, Time.current) }
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def scope?(scope) = scopes.include?(scope.to_s)
end
