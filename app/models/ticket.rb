class Ticket < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  has_many :messages, class_name: "TicketMessage", dependent: :destroy

  enum :status, { open: "open", pending: "pending", resolved: "resolved", closed: "closed" }
  enum :priority, { low: "low", normal: "normal", high: "high" }, prefix: true

  validates :email, :subject, presence: true

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :inbox, -> { where(status: %w[open pending]).order(Arel.sql("CASE priority WHEN 'high' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END"), last_message_at: :desc) }

  def to_param = token

  def touch_activity! = update!(last_message_at: Time.current)
end
