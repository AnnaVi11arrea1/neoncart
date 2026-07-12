module Admin
  class TicketMessagesController < BaseController
    def create
      ticket = Ticket.find_by!(token: params[:ticket_id])
      ticket.messages.create!(body: params.require(:ticket_message)[:body], author_type: "admin", user: current_user)
      redirect_to admin_ticket_path(ticket), notice: "Reply sent + emailed to customer."
    end
  end
end
