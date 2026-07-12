module Api
  module V1
    class OrdersController < BaseController
      # POST /api/v1/orders
      # Two modes:
      #  payment: "checkout" (default) — returns a Stripe checkout_url; the
      #    customer pays there. Requires scope orders:write.
      #  payment: "external" — the partner already collected payment; the
      #    order enters the pipeline as paid and fulfillment starts
      #    immediately. Requires scope orders:write_paid.
      def create
        mode = params.fetch(:payment, "checkout")
        require_scope!(mode == "external" ? "orders:write_paid" : "orders:write")
        return if performed?

        order = build_order!
        if mode == "external"
          order.mark_paid!
          render json: order_json(order), status: :created
        else
          session = Payments::StripeCheckout.session_for(
            order,
            success_url: Rails.configuration.x.store_url + "/checkout/success",
            cancel_url: Rails.configuration.x.store_url + "/checkout/cancel"
          )
          order.update!(stripe_session_id: session.id)
          render json: order_json(order).merge(checkout_url: session.url), status: :created
        end
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "invalid", detail: e.message }, status: :unprocessable_entity
      end

      def show
        unless current_api_key.scope?("orders:read") || current_api_key.scope?("orders:write")
          require_scope!("orders:read")
          return
        end

        order = Order.find_by!(number: params[:number])
        render json: order_json(order)
      end

      private

      def build_order!
        payload = params.require(:order)
        Order.transaction do
          order = Order.create!(
            email: payload.require(:email),
            source: "api", api_key: current_api_key, currency: "usd",
            shipping_address: payload.fetch(:shipping_address, {}).permit(
              :name, :phone, :line1, :line2, :city, :state, :postal_code, :country
            ).to_h,
            notes: payload[:notes]
          )
          subtotal = 0
          payload.require(:items).each do |item|
            product = Product.active.find_by!(slug: item.require(:product_slug))
            variant = product.variants.find(item[:variant_id]) if item[:variant_id].present?
            qty = item.fetch(:quantity, 1).to_i.clamp(1, 99)
            unit = product.display_price_cents(variant)
            subtotal += unit * qty
            order.order_items.create!(
              product:, variant:, supplier: product.supplier,
              title: variant ? "#{product.title} — #{variant.label}" : product.title,
              sku: variant&.sku, quantity: qty, unit_price_cents: unit
            )
          end
          order.update!(subtotal_cents: subtotal, total_cents: subtotal)
          order.log_event!("placed", "Order placed via API (#{current_api_key.name})")
          order
        end
      end

      def order_json(order)
        {
          order: {
            number: order.number, status: order.status,
            total_cents: order.total_cents, currency: order.currency,
            items: order.order_items.map { |i| { title: i.title, sku: i.sku, quantity: i.quantity, unit_price_cents: i.unit_price_cents, fulfillment_status: i.fulfillment_status } },
            shipments: order.shipments.map { |s| { carrier: s.carrier, tracking_number: s.tracking_number, tracking_url: s.tracking_url, status: s.status } },
            status_url: Rails.configuration.x.store_url + "/orders/#{order.number}"
          }
        }
      end
    end
  end
end
