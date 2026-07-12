class TicketMessagesController < ApplicationController
  def create
    ticket = Ticket.find_by!(token: params[:ticket_token])
    authorized = (user_signed_in? && ticket.user_id == current_user.id) ||
                 Array(session[:ticket_tokens]).include?(ticket.token)
    return redirect_to(new_ticket_path, alert: "Not allowed.") unless authorized

    ticket.messages.create!(body: params.require(:ticket_message)[:body], author_type: "customer", user: current_user)
    redirect_to ticket_path(ticket), notice: "Reply sent."
  end
end
