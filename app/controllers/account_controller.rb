# The "why create an account" hub: past orders, saved favorites, and store
# credit balance/history all live on one page.
class AccountController < ApplicationController
  before_action :authenticate_user!

  def show
    @orders = current_user.orders.recent.limit(5)
    @favorites = current_user.favorites.includes(:product).order(created_at: :desc)
    @credit_transactions = current_user.store_credit_transactions.recent.limit(20)
  end
end
