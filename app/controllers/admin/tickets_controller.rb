module Admin
  class TicketsController < BaseController
    def index
      scope = params[:status].present? ? Ticket.where(status: params[:status]).order(last_message_at: :desc) : Ticket.inbox
      @pagy, @tickets = pagy(scope, limit: 30)
    end

    def show
      @ticket = Ticket.find_by!(token: params[:id])
      @messages = @ticket.messages.order(:created_at)
    end

    def update
      ticket = Ticket.find_by!(token: params[:id])
      ticket.update!(params.require(:ticket).permit(:status, :priority))
      redirect_to admin_ticket_path(ticket), notice: "Updated."
    end
  end
end
