class TicketsController < ApplicationController
  def index
    redirect_to(new_ticket_path) && return unless user_signed_in?

    @tickets = current_user.tickets.order(last_message_at: :desc)
  end

  def new
    # Signing in from the form's "Sign in" link should come straight back here.
    store_location_for(:user, request.fullpath) unless user_signed_in?
    @ticket = Ticket.new(email: current_user&.email, name: current_user&.display_name, order_id: params[:order_id])
  end

  # Every ticket belongs to an account. A guest picks a password on the form,
  # which creates the account (or signs in to the one they already have) and
  # signs them in, so the ticket and its replies stay with them.
  def create
    @ticket = Ticket.new(ticket_params.except(:body))
    @ticket.email = current_user.email if user_signed_in?

    @ticket.validate
    @ticket.errors.add(:base, "Tell us how we can help.") if ticket_params[:body].blank?
    unless Recaptcha.verified?(params["g-recaptcha-response"], remote_ip: request.remote_ip)
      @ticket.errors.add(:base, "Tick \"I'm not a robot\" before sending.")
    end
    return render(:new, status: :unprocessable_entity) if @ticket.errors.any?

    @ticket.user = current_user || guest_account
    return render(:new, status: :unprocessable_entity) unless @ticket.user

    @ticket.save!
    @ticket.messages.create!(body: ticket_params[:body], author_type: "customer", user: @ticket.user)
    session[:ticket_tokens] = Array(session[:ticket_tokens]).push(@ticket.token).last(20)
    redirect_to ticket_path(@ticket), notice: "Ticket opened — we'll reply by email and here."
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

  def account_params
    params.fetch(:account, {}).permit(:password, :password_confirmation)
  end

  # Signs the guest in and returns their account, or adds the reason to the
  # ticket's errors and returns nil.
  def guest_account
    email = @ticket.email.to_s.strip.downcase

    if (user = User.find_by(email:))
      if user.valid_password?(account_params[:password].to_s)
        sign_in(user)
        return user
      end
      @ticket.errors.add(:base, "There's already an account for #{email}. Enter its password, or sign in first.")
      return
    end

    unless EmailDeliverability.deliverable?(email)
      @ticket.errors.add(:email, "can't receive mail. Check it for typos.")
      return
    end

    # to_s on both: Devise skips the confirmation check when it's nil.
    user = User.new(email:, name: @ticket.name.presence,
                    password: account_params[:password].to_s,
                    password_confirmation: account_params[:password_confirmation].to_s)
    unless user.save
      user.errors.full_messages.each { |message| @ticket.errors.add(:base, message) }
      return
    end
    sign_in(user)
    user
  end
end
