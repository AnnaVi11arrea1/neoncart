module Dropshipping
  # A configurable REST adapter for POD suppliers whose APIs are gated
  # behind partner approval (ThisNew, ArtsAdd, Yoycol). They all follow the
  # same shape — list products, create order, poll order for tracking — so
  # once you receive partner API docs, you usually only need to set the
  # supplier's api_base_url + credentials and adjust the endpoint paths /
  # JSON keys in `settings` (no code changes for simple cases).
  #
  # settings keys (all optional, shown with defaults):
  #   products_path: "products"          orders_path: "orders"
  #   order_status_path: "orders/%{id}"  auth_style: "bearer" | "header" | "query"
  #   auth_header: "Authorization"       auth_query_param: "api_key"
  #   items_key: "data"                  id_key: "id"
  #   title_key: "title"                 price_key: "price"        price_unit: "cents" | "dollars"
  #   images_key: "images"               variants_key: "variants"
  #   tracking_key: "shipments"          carrier_key: "carrier"
  #   tracking_number_key: "tracking_number"
  #
  # Until a supplier's API access is granted, set its fulfillment_mode to
  # "manual" — its order items land in Admin → Fulfillment Queue, and you
  # paste the tracking number after placing the order on their site.
  # Everything downstream (emails, webhooks, tracking page) stays automated.
  class GenericPodAdapter < BaseAdapter
    BASE_URL = "https://override-me.example.com".freeze

    def test_connection!
      require_credentials!
      raise NotConfigured, "Set this supplier's api_base_url first." if supplier.api_base_url.blank?

      resp = http.get(setting("products_path", "products"), page: 1, **query_auth)
      raise Error, "#{supplier.name} responded HTTP #{resp.status}" unless resp.success?

      true
    end

    def sync_products!
      require_credentials!
      resp = http.get(setting("products_path", "products"), page: 1, **query_auth)
      raise Error, "#{supplier.name} products fetch failed (HTTP #{resp.status})" unless resp.success?

      items = dig_list(resp.body, setting("items_key", "data"))
      items.each do |p|
        upsert_product!(
          external_id: p[setting("id_key", "id")],
          title: p[setting("title_key", "title")].to_s,
          description: p["description"],
          price_cents: to_cents(p[setting("price_key", "price")]),
          image_urls: Array(p[setting("images_key", "images")]).map { |i| i.is_a?(Hash) ? (i["src"] || i["url"]) : i }.compact.first(8),
          variants: Array(p[setting("variants_key", "variants")]).map { |v|
            {
              external_id: v[setting("id_key", "id")],
              sku: v["sku"],
              title: v["title"] || v["name"] || "Default",
              price_cents: to_cents(v[setting("price_key", "price")]),
              available: v.fetch("available", true)
            }
          }
        )
      end
      items.size
    end

    def submit_order!(order, order_items)
      require_credentials!
      addr = order.shipping_address
      body = {
        external_id: "#{order.number}-#{supplier.slug}",
        line_items: order_items.map { |i|
          { product_id: i.product&.external_id, variant_id: i.variant&.external_id, quantity: i.quantity, sku: i.sku }
        },
        shipping_address: {
          name: addr["name"], phone: addr["phone"], email: order.customer_email,
          country: addr["country"], state: addr["state"], city: addr["city"],
          address1: addr["line1"], address2: addr["line2"], zip: addr["postal_code"]
        }
      }
      resp = http.post(setting("orders_path", "orders"), body.merge(query_auth))
      raise Error, "#{supplier.name} order failed (HTTP #{resp.status}): #{resp.body}" unless resp.success?

      (resp.body.dig("data", "id") || resp.body["id"] || resp.body["order_id"]).to_s
    end

    def fetch_tracking(external_order_id)
      require_credentials!
      path = format(setting("order_status_path", "orders/%{id}"), id: external_order_id)
      resp = http.get(path, **query_auth)
      raise Error, "#{supplier.name} order lookup failed (HTTP #{resp.status})" unless resp.success?

      body = resp.body["data"] || resp.body
      Array(body[setting("tracking_key", "shipments")]).map do |s|
        {
          carrier: s[setting("carrier_key", "carrier")],
          tracking_number: s[setting("tracking_number_key", "tracking_number")] || s["number"],
          tracking_url: s["tracking_url"] || s["url"],
          delivered: body["status"].to_s.downcase == "delivered"
        }
      end
    end

    protected

    def setting(key, default) = supplier.settings.fetch(key, default)

    def headers
      base = super
      case setting("auth_style", "bearer")
      when "bearer" then base.merge("Authorization" => "Bearer #{supplier.api_key}")
      when "header" then base.merge(setting("auth_header", "Authorization") => supplier.api_key.to_s)
      else base
      end
    end

    def query_auth
      setting("auth_style", "bearer") == "query" ? { setting("auth_query_param", "api_key") => supplier.api_key } : {}
    end

    def dig_list(body, key)
      list = body.is_a?(Array) ? body : (body[key] || body["items"] || body["products"] || [])
      Array(list)
    end

    def to_cents(value)
      return 0 if value.blank?
      return value.to_i if setting("price_unit", "cents") == "cents"

      (value.to_f * 100).round
    end
  end
end
