class Order < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :api_key, optional: true
  has_many :order_items, dependent: :destroy
  has_many :shipments, dependent: :destroy
  has_many :order_events, -> { order(created_at: :asc) }, dependent: :destroy

  enum :status, {
    pending: "pending",       # created, awaiting payment
    paid: "paid",             # payment confirmed
    processing: "processing", # submitted to suppliers / being fulfilled
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
    refunded: "refunded"
  }

  validates :number, presence: true, uniqueness: true

  before_validation :assign_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :needing_tracking_sync, -> { where(status: %w[processing shipped]) }

  # --- Fulfillment board columns (Admin dashboard) ----------------------
  # NEW: paid, still has items you haven't placed with the supplier yet.
  # PENDING: placed with the supplier, awaiting shipment.
  # COMPLETED: shipped or delivered.
  scope :board_new,       -> { where(status: %w[paid processing], id: OrderItem.awaiting_manual.select(:order_id)) }
  scope :board_pending,   -> { where(status: %w[paid processing]).where.not(id: OrderItem.awaiting_manual.select(:order_id)) }
  scope :board_completed, -> { where(status: %w[shipped delivered]) }

  # --- state transitions -----------------------------------------------
  # Every transition writes an audit event, emails the customer, and
  # fans out to partner webhooks. This is the automation backbone.

  def mark_paid!(payment_intent_id: nil, session_id: nil)
    return if paid? || processing? || shipped? || delivered?

    update!(status: :paid,
            placed_at: placed_at || Time.current,
            stripe_payment_intent_id: payment_intent_id || stripe_payment_intent_id,
            stripe_session_id: session_id || stripe_session_id)
    log_event!("paid", "Payment confirmed")
    OrderMailer.confirmation(self).deliver_later
    Webhooks::Dispatcher.publish("order.paid", webhook_payload)
    DiscordOrderNotificationJob.perform_later(id)
    SubmitOrderToSuppliersJob.perform_later(id)
  end

  def mark_processing!
    return unless paid?

    update!(status: :processing)
    log_event!("submitted", "Sent to suppliers for fulfillment")
    notify_status_change!
  end

  def mark_shipped!
    return if shipped? || delivered?

    update!(status: :shipped)
    log_event!("shipped", "Order shipped")
    OrderMailer.shipped(self).deliver_later
    Webhooks::Dispatcher.publish("order.shipped", webhook_payload)
  end

  def mark_delivered!
    return if delivered?

    update!(status: :delivered)
    log_event!("delivered", "Order delivered")
    notify_status_change!
  end

  def cancel!(reason = nil)
    return if cancelled? || refunded?

    update!(status: :cancelled)
    log_event!("cancelled", reason.presence || "Order cancelled")
    notify_status_change!
  end

  def log_event!(kind, message, data = {})
    order_events.create!(kind:, message:, data:)
  end

  def notify_status_change!
    OrderMailer.status_update(self).deliver_later
    Webhooks::Dispatcher.publish("order.status_changed", webhook_payload)
  end

  # ----------------------------------------------------------------------

  def items_by_supplier
    order_items.includes(:supplier).group_by(&:supplier)
  end

  def customer_email = email.presence || user&.email

  def customer_name
    shipping_address["name"].presence || user&.display_name || "Customer"
  end

  def fully_fulfilled?
    order_items.where.not(fulfillment_status: %w[fulfilled cancelled]).none?
  end

  def webhook_payload
    {
      number: number,
      status: status,
      email: customer_email,
      total_cents: total_cents,
      currency: currency,
      placed_at: placed_at&.iso8601,
      items: order_items.map { |i| { title: i.title, sku: i.sku, quantity: i.quantity, unit_price_cents: i.unit_price_cents, fulfillment_status: i.fulfillment_status } },
      shipments: shipments.map { |s| { carrier: s.carrier, tracking_number: s.tracking_number, tracking_url: s.tracking_url, status: s.status } }
    }
  end

  private

  def assign_number
    self.number ||= loop do
      candidate = "EF-#{Time.current.strftime('%y%m')}-#{SecureRandom.alphanumeric(6).upcase}"
      break candidate unless self.class.exists?(number: candidate)
    end
  end
end
