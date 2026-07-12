module Admin
  class OrdersController < BaseController
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
      redirect_to admin_order_path(@order), notice: "Order cancelled."
    end

    def mark_shipped
      @order.mark_shipped!
      redirect_to admin_order_path(@order), notice: "Marked shipped — customer notified."
    end

    private

    def set_order = @order = Order.find(params[:id])
  end
end
