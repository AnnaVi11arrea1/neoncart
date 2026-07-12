module Admin
  class DashboardController < BaseController
    def index
      @revenue_30d_cents = Order.where(status: %w[paid processing shipped delivered])
                                .where("placed_at > ?", 30.days.ago).sum(:total_cents)
      @orders_by_status = Order.group(:status).count
      @open_tickets = Ticket.inbox.count
      @awaiting_manual = OrderItem.awaiting_manual.count
      @recent_orders = Order.recent.limit(8)
      @recent_events = OrderEvent.includes(:order).order(created_at: :desc).limit(10)
      @suppliers = Supplier.all
    end
  end
end
