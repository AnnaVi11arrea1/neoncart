module Admin
  # Deletes a single uploaded photo (ActiveStorage attachment) from a
  # product. Deliberately its own tiny controller/route rather than folded
  # into ProductsController#update — that action's mass-assignment path is
  # exactly what silently wiped every photo before (see product_photos
  # nowhere near product_params). Removing one photo is a single, explicit
  # purge, scoped through the product so you can't touch another product's
  # attachment by guessing an id.
  class ProductPhotosController < BaseController
    def destroy
      product = Product.find_by!(slug: params[:product_id])
      attachment = product.images_attachments.find(params[:id])
      product.update!(primary_image_id: nil) if product.primary_image_id == attachment.id
      attachment.purge
      redirect_to edit_admin_product_path(product), notice: "Photo removed."
    end
  end
end
