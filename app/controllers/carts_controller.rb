class CartsController < ApplicationController
  def show
    @cart = current_cart

    # Preview mode hands back a stub cart with no items — see
    # ApplicationController#current_cart — so don't assume the association.
    return @items = [] unless @cart.respond_to?(:cart_items)

    # Same ActiveStorage N+1 the product grids had (see Product.with_card_images).
    # `images_attachments` (plural) is the has_many side of `has_many_attached`.
    @items = @cart.cart_items.includes(:variant, product: [:product_images, { images_attachments: :blob }])
  end
end
