class FavoritesController < ApplicationController
  before_action :authenticate_user!

  def create
    product = Product.find(params[:product_id])
    current_user.favorites.find_or_create_by!(product:)
    redirect_back fallback_location: product_path(product.slug), notice: "Saved to favorites."
  end

  def destroy
    current_user.favorites.find(params[:id]).destroy
    redirect_back fallback_location: root_path, notice: "Removed from favorites."
  end
end
