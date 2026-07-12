module Admin
  # Queue of order items waiting on you: manual-mode dropshippers
  # (ThisNew/ArtsAdd/Yoycol until their partner APIs are wired) and
  # in-house products. Mark submitted once you've placed the order on the
  # supplier's site; add tracking from the order page when it ships.
  class FulfillmentsController < BaseController
    def index
      @items = OrderItem.awaiting_manual.includes(:order, :supplier, :product)
                        .joins(:order).where(orders: { status: %w[paid processing] })
                        .order("orders.placed_at ASC")
    end

    def update
      item = OrderItem.find(params[:id])
      item.update!(fulfillment_status: "submitted", external_order_id: params.dig(:order_item, :external_order_id))
      item.order.log_event!("note", "#{item.title}: manually submitted to #{item.supplier&.name || 'in-house'}")
      redirect_to admin_fulfillments_path, notice: "Marked submitted."
    end
  end
end
