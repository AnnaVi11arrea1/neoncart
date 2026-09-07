module Admin
  # In-person (card-present) point-of-sale using Stripe Terminal.
  # Client flow lives in app/javascript/controllers/terminal_controller.js and
  # follows https://docs.stripe.com/terminal/quickstart?platform=web
  #
  # Server responsibilities (the three endpoints Terminal needs):
  #   connection_token — hands the JS SDK a short-lived token to talk to Stripe
  #   payment_intent   — builds the order + a card_present PaymentIntent
  #   capture          — captures the authorized payment and marks the order paid
  class TerminalController < BaseController
    def show
      @products = Product.active.includes(:variants).order(:title)
    end

    # The SDK calls this (via our JS onFetchConnectionToken) on connect.
    def connection_token
      token = Stripe::Terminal::ConnectionToken.create
      render json: { secret: token.secret }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # Create the order and a manual-capture card_present PaymentIntent.
    # The amount is computed server-side from catalog prices so a tampered
    # client can't change what gets charged.
    def payment_intent
      order = build_order!
      intent = Stripe::PaymentIntent.create(
        amount: order.total_cents,
        currency: order.currency,
        payment_method_types: ["card_present"],
        capture_method: "manual",
        metadata: { order_number: order.number, channel: "in_person" }
      )
      order.update!(stripe_payment_intent_id: intent.id)
      render json: {
        client_secret: intent.client_secret,
        payment_intent_id: intent.id,
        order_number: order.number,
        amount: order.total_cents
      }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # After the reader collects the card and the SDK processes the payment
    # (leaving it in requires_capture), capture it and finalize the order.
    def capture
      order = Order.find_by!(stripe_payment_intent_id: params[:payment_intent_id])
      intent = Stripe::PaymentIntent.capture(params[:payment_intent_id])
      if intent.status == "succeeded"
        complete_in_person_sale!(order, intent)
        render json: { status: "succeeded", order_number: order.number }
      else
        render json: { status: intent.status, error: "Payment not captured (#{intent.status})" },
               status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Order not found for that payment." }, status: :not_found
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def build_order!
      items = Array(params[:items])
      custom_cents = params[:custom_cents].to_i
      raise ArgumentError, "Add a product or a custom amount before charging." if items.blank? && custom_cents <= 0

      ship = shipping_params
      order = Order.create!(currency: "usd", email: params[:email].presence,
                            status: "pending", subtotal_cents: 0, total_cents: 0,
                            shipping_address: ship)
      total = 0
      needs_shipping = false

      items.each do |raw|
        it = raw.respond_to?(:permit) ? raw.permit(:slug, :variant_id, :quantity) : raw.to_h.symbolize_keys
        product = Product.active.find_by(slug: it[:slug])
        next unless product

        variant = product.variants.find_by(id: it[:variant_id]) if it[:variant_id].present?
        qty = [it[:quantity].to_i, 1].max
        unit = variant&.price_cents.presence || product.price_cents
        order.order_items.create!(
          product: product, variant: variant, supplier: product.supplier,
          title: [product.title, variant&.title].compact.reject(&:blank?).uniq.join(" — "),
          sku: variant&.sku, quantity: qty, unit_price_cents: unit, fulfillment_status: "unfulfilled"
        )
        total += unit * qty
        needs_shipping = true if product.supplier_id.present? # POD/dropship must ship
      end

      if custom_cents.positive?
        order.order_items.create!(title: params[:custom_label].presence || "In-store item",
                                  quantity: 1, unit_price_cents: custom_cents, fulfillment_status: "unfulfilled")
        total += custom_cents
      end

      if total <= 0
        order.destroy
        raise ArgumentError, "Nothing to charge."
      end
      if needs_shipping && ship.blank?
        order.destroy
        raise ArgumentError, "This sale includes print-on-demand items that must ship — add the customer's shipping address."
      end

      order.update!(subtotal_cents: total, total_cents: total)
      order.log_event!("placed", "In-person sale started")
      order
    end

    def shipping_params
      raw = params[:shipping]
      return {} if raw.blank?

      h = raw.permit(:name, :phone, :line1, :line2, :city, :state, :postal_code, :country)
             .to_h.reject { |_, v| v.blank? }
      h["country"] = "US" if h.present? && h["country"].blank?
      h
    end

    # Finalize an in-person sale. Items that need shipping — anything from a
    # supplier (print-on-demand/dropship), or in-house items when a shipping
    # address was entered — go to the Fulfillment queue + dashboard "New"
    # column (awaiting_manual). Items with no supplier and no address are a
    # counter sale (handed over) and marked fulfilled.
    def complete_in_person_sale!(order, intent)
      return unless order.pending?

      order.update!(status: "paid", placed_at: Time.current, stripe_payment_intent_id: intent.id)

      order.order_items.where.not(supplier_id: nil).update_all(fulfillment_status: "awaiting_manual")
      in_house_status = order.shipping_address.present? ? "awaiting_manual" : "fulfilled"
      order.order_items.where(supplier_id: nil).update_all(fulfillment_status: in_house_status)

      order.log_event!("paid", "In-person card payment captured (#{intent.id})")
      OrderMailer.confirmation(order).deliver_later if order.customer_email.present?
      Webhooks::Dispatcher.publish("order.paid", order.webhook_payload)
    end
  end
end
