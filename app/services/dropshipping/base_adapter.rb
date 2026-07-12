module Dropshipping
  # Contract every supplier adapter implements. Add a new dropshipper by
  # subclassing this (or GenericPodAdapter), then registering it in
  # Dropshipping::Registry. The rest of the app (jobs, admin, emails,
  # webhooks) needs no changes.
  class BaseAdapter
    class Error < StandardError; end
    class NotConfigured < Error; end

    attr_reader :supplier

    def initialize(supplier)
      @supplier = supplier
    end

    # Pull catalog from the supplier and upsert Product/Variant records.
    # Returns count of products synced.
    def sync_products!
      raise NotImplementedError
    end

    # Submit the given order_items (all belonging to this supplier) for
    # fulfillment. Must return the supplier's external order id (String).
    def submit_order!(order, order_items)
      raise NotImplementedError
    end

    # Return an array of tracking hashes for a previously submitted order:
    # [{ carrier:, tracking_number:, tracking_url:, delivered: bool }]
    def fetch_tracking(external_order_id)
      raise NotImplementedError
    end

    # Cheap connectivity/credentials check. Returns true or raises Error.
    def test_connection!
      raise NotImplementedError
    end

    protected

    def http
      @http ||= Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.timeout = 30
        f.options.open_timeout = 10
        headers.each { |k, v| f.headers[k] = v }
      end
    end

    def base_url = supplier.api_base_url.presence || self.class::BASE_URL

    def headers
      { "User-Agent" => "Neoncart/1.0" }
    end

    def require_credentials!
      raise NotConfigured, "#{supplier.name}: API credentials missing. Add them in Admin → Suppliers." unless supplier.credentials_present?
    end

    def upsert_product!(external_id:, title:, description: nil, price_cents: 0, image_urls: [], variants: [], tags: [])
      product = Product.find_or_initialize_by(supplier: supplier, external_id: external_id.to_s)
      is_new = product.new_record?
      product.assign_attributes(title:, description:, price_cents:, tags:)
      product.status = "draft" if is_new # new imports need review before going live
      product.save!

      image_urls.each_with_index do |url, i|
        img = product.product_images.find_or_initialize_by(remote_url: url)
        img.position = i
        img.save!
      end
      product.product_images.where.not(remote_url: image_urls).destroy_all if image_urls.any?

      seen = []
      variants.each_with_index do |v, i|
        variant = product.variants.find_or_initialize_by(external_id: v[:external_id].to_s)
        variant.assign_attributes(
          sku: v[:sku], title: v[:title] || "Default", options: v[:options] || {},
          price_cents: v[:price_cents], available: v.fetch(:available, true), position: i
        )
        variant.save!
        seen << variant.id
      end
      product.variants.where.not(id: seen).update_all(available: false) if variants.any?

      Webhooks::Dispatcher.publish("product.updated", { slug: product.slug, title: product.title, supplier: supplier.slug })
      product
    end
  end
end
