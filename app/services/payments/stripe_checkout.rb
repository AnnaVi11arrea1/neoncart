module Payments
  # Builds a Stripe Checkout Session for an Order. Stripe Checkout serves
  # card, Google Pay, Apple Pay, Link, Cash App Pay etc. automatically —
  # enable/disable wallets in the Stripe Dashboard, no code changes needed.
  class StripeCheckout
    def self.session_for(order, success_url:, cancel_url:)
      Stripe::Checkout::Session.create(
        mode: "payment",
        client_reference_id: order.number,
        customer_email: order.customer_email,
        line_items: order.order_items.map { |item|
          {
            quantity: item.quantity,
            price_data: {
              currency: order.currency,
              unit_amount: item.unit_price_cents,
              product_data: { name: item.title }.tap { |pd|
                url = item.product&.primary_image_url
                pd[:images] = [absolute(url)] if url&.start_with?("http")
              }
            }
          }
        },
        shipping_address_collection: {
          allowed_countries: ENV.fetch("SHIP_COUNTRIES", "US,CA").split(",").map(&:strip)
        },
        shipping_options: shipping_options,
        automatic_tax: { enabled: stripe_tax_enabled? },
        phone_number_collection: { enabled: true },
        metadata: { order_number: order.number },
        success_url: "#{success_url}?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: cancel_url
      )
    end

    def self.shipping_options
      flat = ENV.fetch("FLAT_SHIPPING_CENTS", "599").to_i
      free_over = ENV.fetch("FREE_SHIPPING_OVER_CENTS", "0").to_i
      opts = [{
        shipping_rate_data: {
          type: "fixed_amount",
          display_name: flat.zero? ? "Free shipping" : "Standard shipping",
          fixed_amount: { amount: flat, currency: "usd" },
          delivery_estimate: {
            minimum: { unit: "business_day", value: 5 },
            maximum: { unit: "business_day", value: 12 }
          }
        }
      }]
      opts
    end

    def self.absolute(url)
      url.start_with?("http") ? url : "#{Rails.configuration.x.store_url}#{url}"
    end

    # Off by default — turning this on requires Stripe Tax to be configured
    # in the Dashboard first (Settings -> Tax: an origin address plus at
    # least one state registration). Enabling automatic_tax without that
    # setup fails every checkout, so this stays false until you flip
    # ENABLE_STRIPE_TAX=true yourself once that's done.
    def self.stripe_tax_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["ENABLE_STRIPE_TAX"])
    end
  end
end
