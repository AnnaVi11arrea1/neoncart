module Admin
  class ProductsController < BaseController
    before_action :set_product, only: %i[edit update destroy archive]

    def index
      scope = Product.includes(:supplier, :category).order(updated_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.search(params[:q])
      @pagy, @products = pagy(scope, limit: 30)
    end

    def new
      @product = Product.new(status: "active", currency: "usd")
      @product.variants.build(title: "Default")
    end

    def create
      @product = Product.new(product_params)
      if @product.save
        @product.images.attach(new_image_uploads)
        redirect_to edit_admin_product_path(@product), notice: "Product created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @product.update(product_params)
        @product.images.attach(new_image_uploads)
        redirect_to edit_admin_product_path(@product), notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def archive
      @product.archived!
      redirect_to admin_products_path, notice: "Archived."
    end

    def destroy
      @product.destroy!
      redirect_to admin_products_path, notice: "Deleted."
    end

    private

    def set_product
      @product = Product.find_by!(slug: params[:id])
    end

    # Images are deliberately NOT in product_params. has_many_attached=
    # treats any mass-assignment — even an untouched file input's blank
    # submission, even a single real upload — as "replace the whole
    # collection," which silently destroyed every existing photo on save.
    # Uploads are additive: pulled from raw params and .attach()ed
    # separately after save, which only ever adds.
    def new_image_uploads
      Array(params.dig(:product, :images)).select { |f| f.respond_to?(:original_filename) }
    end

    def product_params
      permitted = params.require(:product).permit(
        :title, :description, :category_id, :status, :featured, :primary_image_id,
        :price_dollars, :compare_at_dollars, :tag_list,
        variants_attributes: %i[id title sku price_dollars available _destroy]
      )
      translate_money!(permitted)
      permitted
    end

    def translate_money!(p)
      p[:price_cents] = (p.delete(:price_dollars).to_f * 100).round if p[:price_dollars].present?
      p[:compare_at_price_cents] = (p.delete(:compare_at_dollars).to_f * 100).round if p[:compare_at_dollars].present?
      p[:tags] = p.delete(:tag_list).to_s.split(",").map { |t| t.strip.downcase }.reject(&:empty?) if p.key?(:tag_list)
      if p[:variants_attributes].is_a?(ActionController::Parameters)
        p[:variants_attributes].each_value do |v|
          v[:price_cents] = (v.delete(:price_dollars).to_f * 100).round if v[:price_dollars].present?
        end
      end
    end
  end
end
