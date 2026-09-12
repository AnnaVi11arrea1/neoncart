class CartItemsController < ApplicationController
  def create
    product = Product.active.find(params[:product_id])
    variant = product.variants.available.find_by(id: params[:variant_id]) if params[:variant_id].present?

    # Never bank an order we can't fulfil: if the product is sold by variant,
    # an available one has to be picked.
    if variant.nil? && product.variants.exists?
      return redirect_to product_path(product.slug), alert: "Pick an available option first."
    end

    quantity = params.fetch(:quantity, 1).to_i.clamp(1, 99)
    current_cart.add(product, variant:, quantity:)

    # The add happens here but the browser lands on the cart, so the GA4 event
    # rides along in the flash and shared/_analytics renders it there.
    flash[:ga_event] = {
      "name" => "add_to_cart",
      "params" => {
        "currency" => product.currency.to_s.upcase,
        "value" => helpers.ga_price((variant&.price_cents_or_default || product.price_cents) * quantity),
        "items" => [helpers.ga_item(product, variant:, quantity:).deep_stringify_keys]
      }
    }
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
