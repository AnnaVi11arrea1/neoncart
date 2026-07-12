module Dropshipping
  # Fully wired against Printify's public REST API v1.
  # Docs: https://developers.printify.com
  # Setup: create a Personal Access Token in Printify → My Profile →
  # Connections, paste it as the supplier's api_key, then click
  # "Test connection" (auto-detects your shop_id) and "Sync now".
  class PrintifyAdapter < BaseAdapter
    BASE_URL = "https://api.printify.com/v1".freeze

    def test_connection!
      require_credentials!
      resp = http.get("shops.json")
      raise Error, "Printify auth failed (HTTP #{resp.status})" unless resp.success?

      shops = resp.body
      if supplier.shop_id.blank? && shops.is_a?(Array) && shops.any?
        supplier.update!(shop_id: shops.first["id"].to_s)
      end
      true
    end

    def sync_products!
      require_credentials!
      ensure_shop_id!
      count = 0
      page = 1
      loop do
        resp = http.get("shops/#{supplier.shop_id}/products.json", page: page, limit: 50)
        raise Error, "Printify products fetch failed (HTTP #{resp.status})" unless resp.success?

        data = resp.body["data"] || []
        break if data.empty?

        data.each do |p|
          next unless p["visible"]

          upsert_product!(
            external_id: p["id"],
            title: p["title"],
            description: p["description"],
            price_cents: p.dig("variants", 0, "price").to_i,
            image_urls: Array(p["images"]).map { |i| i["src"] }.compact.first(8),
            tags: Array(p["tags"]).map(&:downcase).first(10),
            variants: Array(p["variants"]).select { |v| v["is_enabled"] }.map { |v|
              {
                external_id: v["id"],
                sku: v["sku"],
                title: v["title"],
                price_cents: v["price"].to_i,
                available: v["is_available"]
              }
            }
          )
          count += 1
        end
        break if data.size < 50

        page += 1
      end
      count
    end

    def submit_order!(order, order_items)
      require_credentials!
      ensure_shop_id!
      addr = order.shipping_address
      name_parts = addr["name"].to_s.split(" ", 2)

      body = {
        external_id: "#{order.number}-#{supplier.slug}",
        label: order.number,
        line_items: order_items.map { |item|
          {
            product_id: item.product&.external_id,
            variant_id: item.variant&.external_id.to_i,
            quantity: item.quantity
          }
        },
        shipping_method: supplier.settings.fetch("shipping_method", 1).to_i,
        send_shipping_notification: false, # we send our own branded emails
        address_to: {
          first_name: name_parts[0].to_s,
          last_name: name_parts[1].to_s,
          email: order.customer_email,
          phone: addr["phone"].to_s,
          country: addr["country"].to_s,
          region: addr["state"].to_s,
          address1: addr["line1"].to_s,
          address2: addr["line2"].to_s,
          city: addr["city"].to_s,
          zip: addr["postal_code"].to_s
        }
      }

      resp = http.post("shops/#{supplier.shop_id}/orders.json", body)
      raise Error, "Printify order failed (HTTP #{resp.status}): #{resp.body}" unless resp.success?

      resp.body["id"].to_s
    end

    def fetch_tracking(external_order_id)
      require_credentials!
      ensure_shop_id!
      resp = http.get("shops/#{supplier.shop_id}/orders/#{external_order_id}.json")
      raise Error, "Printify order lookup failed (HTTP #{resp.status})" unless resp.success?

      status = resp.body["status"].to_s
      Array(resp.body["shipments"]).map do |s|
        {
          carrier: s["carrier"],
          tracking_number: s["number"],
          tracking_url: s["url"],
          delivered: status == "delivered"
        }
      end
    end

    protected

    def headers
      super.merge("Authorization" => "Bearer #{supplier.api_key}")
    end

    def ensure_shop_id!
      test_connection! if supplier.shop_id.blank?
      raise NotConfigured, "Printify shop_id missing — run Test connection first." if supplier.shop_id.blank?
    end
  end
end
