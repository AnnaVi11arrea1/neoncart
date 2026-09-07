module Admin
  class OrdersController < BaseController
    include Boardable
    before_action :set_order, except: :index

    def index
      scope = Order.recent.includes(:order_items)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where("number ILIKE :q OR email ILIKE :q", q: "%#{params[:q]}%") if params[:q].present?
      @pagy, @orders = pagy(scope, limit: 30)
    end

    def show; end

    def resubmit
      SubmitOrderToSuppliersJob.perform_later(@order.id)
      redirect_to admin_order_path(@order), notice: "Resubmission queued."
    end

    def cancel
      @order.cancel!(params[:reason].presence || "Cancelled by admin")
      redirect_back fallback_location: admin_order_path(@order), notice: "Order #{@order.number} cancelled."
    end

    def mark_shipped
      @order.mark_shipped!
      redirect_to admin_order_path(@order), notice: "Marked shipped — customer notified."
    end

    # Dashboard board: New -> Pending. You've placed the order on the
    # supplier's site (e.g. ArtsAdd); record their order # and move it along.
    def mark_placed
      ext = params[:external_order_id].presence
      @order.order_items.awaiting_manual.update_all(fulfillment_status: "submitted", external_order_id: ext)
      @order.mark_processing! if @order.paid?
      @order.log_event!("submitted", "Placed with supplier#{" · ##{ext}" if ext}")
      respond_board("#{@order.number}: marked placed.")
    end

    # Dashboard board: Pending -> Completed. Add tracking, mark items
    # fulfilled, mark the order shipped, and email the customer.
    def ship
      if params[:tracking_number].present?
        @order.shipments.create!(
          carrier: params[:carrier].presence, tracking_number: params[:tracking_number],
          shipped_at: Time.current
        )
      end
      @order.order_items.where.not(fulfillment_status: "cancelled").update_all(fulfillment_status: "fulfilled")
      @order.mark_shipped!
      respond_board("#{@order.number}: shipped — customer notified.")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      redirect_back fallback_location: admin_root_path, alert: e.message
    end

    private

    def set_order = @order = Order.find(params[:id])
  end
end
