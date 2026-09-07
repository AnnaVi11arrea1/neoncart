module Admin
  class DashboardController < BaseController
    include Boardable

    def index
      @revenue_30d_cents = Order.where(status: %w[paid processing shipped delivered])
                                .where("placed_at > ?", 30.days.ago).sum(:total_cents)
      @open_tickets = Ticket.inbox.count
      @awaiting_manual = OrderItem.awaiting_manual.count
      @recent_events = OrderEvent.includes(:order).order(created_at: :desc).limit(8)
      load_board
    end
  end
end
