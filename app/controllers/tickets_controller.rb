class TicketsController < ApplicationController
  def index
    redirect_to(new_ticket_path) && return unless user_signed_in?

    @tickets = current_user.tickets.order(last_message_at: :desc)
  end

  def new
    @ticket = Ticket.new(email: current_user&.email, name: current_user&.display_name, order_id: params[:order_id])
  end

  def create
    @ticket = Ticket.new(ticket_params.except(:body))
    @ticket.user = current_user
    if @ticket.save
      @ticket.messages.create!(body: ticket_params[:body], author_type: "customer", user: current_user)
      session[:ticket_tokens] = Array(session[:ticket_tokens]).push(@ticket.token).last(20)
      redirect_to ticket_path(@ticket), notice: "Ticket opened — we'll reply by email and here."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @ticket = Ticket.find_by!(token: params[:token])
    authorized = (user_signed_in? && @ticket.user_id == current_user.id) ||
                 Array(session[:ticket_tokens]).include?(@ticket.token)
    redirect_to new_ticket_path, alert: "Ticket not found." unless authorized
  end

  private

  def ticket_params
    params.require(:ticket).permit(:email, :name, :subject, :order_id, :body)
  end
end
