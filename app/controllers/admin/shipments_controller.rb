module Admin
  class ShipmentsController < BaseController
    # Manual tracking entry (for manual-mode suppliers / in-house items)
    def create
      order = Order.find(params[:order_id])
      shipment = order.shipments.create!(shipment_params)
      order.order_items.awaiting_manual.update_all(fulfillment_status: "fulfilled") if params[:fulfill_manual] == "1"
      order.mark_shipped!
      redirect_to admin_order_path(order), notice: "Tracking #{shipment.tracking_number} added — customer emailed."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      redirect_to admin_order_path(params[:order_id]), alert: e.message
    end

    private

    def shipment_params
      params.require(:shipment).permit(:carrier, :tracking_number, :tracking_url).merge(shipped_at: Time.current)
    end
  end
end
