class CartItemsController < ApplicationController
  def create
    product = Product.active.find(params[:product_id])
    variant = product.variants.find(params[:variant_id]) if params[:variant_id].present?
    current_cart.add(product, variant:, quantity: params.fetch(:quantity, 1).to_i.clamp(1, 99))
    redirect_to cart_path, notice: "Added to cart."
  end

  def update
    item = current_cart.cart_items.find(params[:id])
    qty = params.dig(:cart_item, :quantity).to_i
    qty.positive? ? item.update!(quantity: qty.clamp(1, 99)) : item.destroy!
    redirect_to cart_path
  end

  def destroy
    current_cart.cart_items.find(params[:id]).destroy!
    redirect_to cart_path, notice: "Removed."
  end
end
