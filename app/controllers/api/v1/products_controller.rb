module Api
  module V1
    class ProductsController < BaseController
      before_action { require_scope!("products:read") }

      def index
        scope = Product.storefront.includes(:variants, :product_images, :category)
        scope = scope.search(params[:q])
        products = scope.limit(params.fetch(:limit, 50).to_i.clamp(1, 100))
                        .offset(params.fetch(:offset, 0).to_i)
        render json: { products: products.map { |p| serialize(p) } }
      end

      def show
        product = Product.active.find_by!(slug: params[:slug])
        render json: { product: serialize(product, full: true) }
      end

      private

      def serialize(p, full: false)
        base = {
          slug: p.slug, title: p.title, price_cents: p.price_cents,
          currency: p.currency, category: p.category&.slug, tags: p.tags,
          image_urls: p.all_image_urls,
          url: Rails.configuration.x.store_url + "/products/#{p.slug}"
        }
        if full
          base[:description] = p.description
          base[:variants] = p.variants.available.map { |v|
            { id: v.id, sku: v.sku, title: v.label, price_cents: v.price_cents_or_default, options: v.options }
          }
        end
        base
      end
    end
  end
end
