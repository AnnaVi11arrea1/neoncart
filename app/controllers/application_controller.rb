class ApplicationController < ActionController::Base
  include Pagy::Backend

  helper_method :current_cart, :store_name, :store_email, :preview_mode?

  private

  def current_cart
    return Struct.new(:item_count).new(0) if preview_mode?

    @current_cart ||= begin
      cart = Cart.find_by(token: session[:cart_token]) if session[:cart_token]
      cart ||= Cart.create!(user: current_user)
      cart.update!(user: current_user) if current_user && cart.user_id.nil?
      session[:cart_token] = cart.token
      cart
    end
  end

  def store_name = Rails.configuration.x.store_name

  def store_email = Rails.configuration.x.store_email

  def preview_mode?
    ENV.fetch("PREVIEW_MODE", Rails.env.development? ? "1" : "0") == "1"
  end

  def require_admin!
    unless current_user&.admin?
      redirect_to new_user_session_path, alert: "Admin access required."
    end
  end
end
