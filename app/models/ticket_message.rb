class TicketMessage < ApplicationRecord
  belongs_to :ticket
  belongs_to :user, optional: true

  validates :body, presence: true
  validates :author_type, inclusion: { in: %w[customer admin] }

  after_create_commit :notify

  def from_admin? = author_type == "admin"

  private

  def notify
    ticket.touch_activity!
    if from_admin?
      ticket.update!(status: :pending) if ticket.open?
      TicketMailer.reply(self).deliver_later
    else
      ticket.update!(status: :open)
      TicketMailer.admin_alert(self).deliver_later
    end
  end
end
