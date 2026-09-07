module Admin
  # Shared loading + Turbo response for the interactive fulfillment board on
  # the admin dashboard. Actions that move an order between columns call
  # respond_board, which re-renders the whole board over Turbo (or redirects
  # back for non-Turbo requests).
  module Boardable
    extend ActiveSupport::Concern

    private

    def load_board
      @board_new       = Order.board_new.recent.includes(:order_items)
      @board_pending   = Order.board_pending.recent.includes(:order_items)
      @board_completed = Order.board_completed.recent.includes(:order_items, :shipments).limit(25)
    end

    def respond_board(notice)
      load_board
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("order-board", partial: "admin/dashboard/board")
        end
        format.html { redirect_back fallback_location: admin_root_path, notice: notice }
      end
    end
  end
end
