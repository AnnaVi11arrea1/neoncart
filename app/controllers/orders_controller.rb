class OrdersController < ApplicationController
  def index
    redirect_to(new_user_session_path, alert: "Sign in to see your orders.") && return unless user_signed_in?

    @orders = current_user.orders.recent
  end

  def show
    @order = Order.find_by!(number: params[:number])
    authorized = (user_signed_in? && @order.user_id == current_user.id) ||
                 session[:order_access] == @order.number
    redirect_to order_lookup_path, alert: "Look up your order with its number and email." unless authorized
  end

  def lookup; end

  def find
    order = Order.find_by(number: params[:number].to_s.strip.upcase)
    if order && order.customer_email.to_s.casecmp?(params[:email].to_s.strip)
      session[:order_access] = order.number
      redirect_to order_path(order.number)
    else
      redirect_to order_lookup_path, alert: "No order matches that number and email."
    end
  end
end
