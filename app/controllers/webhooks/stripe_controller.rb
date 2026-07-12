module Webhooks
  class StripeController < ActionController::API
    def create
      event = Stripe::Webhook.construct_event(
        request.body.read,
        request.env["HTTP_STRIPE_SIGNATURE"],
        ENV["STRIPE_WEBHOOK_SECRET"]
      )

      case event.type
      when "checkout.session.completed", "checkout.session.async_payment_succeeded"
        session = event.data.object
        order = Order.find_by(stripe_session_id: session.id) ||
                Order.find_by(number: session.client_reference_id)
        if order&.pending?
          capture_shipping(order, session)
          order.mark_paid!(payment_intent_id: session.payment_intent, session_id: session.id)
        end
      when "checkout.session.async_payment_failed"
        session = event.data.object
        Order.find_by(stripe_session_id: session.id)&.cancel!("Payment failed")
      end

      head :ok
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
    end

    private

    def capture_shipping(order, session)
      details = session.customer_details
      ship = session.try(:shipping_details) || session.try(:collected_information)&.try(:shipping_details)
      addr = ship&.address || details&.address
      order.update!(
        email: order.email.presence || details&.email,
        shipping_address: {
          "name" => ship&.name || details&.name,
          "phone" => details&.phone,
          "line1" => addr&.line1, "line2" => addr&.line2,
          "city" => addr&.city, "state" => addr&.state,
          "postal_code" => addr&.postal_code, "country" => addr&.country
        }.compact,
        shipping_cents: session.try(:shipping_cost)&.try(:amount_total).to_i,
        total_cents: session.amount_total.to_i
      )
    end
  end
end
