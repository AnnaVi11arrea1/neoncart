class CheckoutsController < ApplicationController
  def create
    cart = current_cart
    return redirect_to(cart_path, alert: "Your cart is empty.") if cart.empty?

    order = build_order_from(cart)
    session_obj = Payments::StripeCheckout.session_for(
      order,
      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url,
      credit_cents: order.credit_applied_cents
    )
    order.update!(stripe_session_id: session_obj.id)
    redirect_to session_obj.url, allow_other_host: true, status: :see_other
  rescue Stripe::StripeError => e
    redirect_to cart_path, alert: "Payment error: #{e.message}"
  end

  def success
    @order = Order.find_by(stripe_session_id: params[:session_id])
    # Webhook is the source of truth, but confirm eagerly for instant UX:
    if @order&.pending?
      s = Stripe::Checkout::Session.retrieve(params[:session_id])
      if s.payment_status == "paid"
        capture_shipping(@order, s)
        @order.mark_paid!(payment_intent_id: s.payment_intent, session_id: s.id)
      end
    end
    if @order && !@order.pending?
      @order_items = @order.order_items.includes(:variant, product: :category)
      session[:order_access] = @order.number
      session.delete(:cart_token)
    end
  end

  def cancel
    redirect_to cart_path, alert: "Checkout cancelled — your cart is untouched."
  end

  private

  def build_order_from(cart)
    Order.create!(user: current_user, email: current_user&.email, currency: "usd",
                  subtotal_cents: cart.subtotal_cents, total_cents: cart.subtotal_cents,
                  credit_applied_cents: credit_to_apply(cart)).tap do |order|
      cart.cart_items.includes(:product, :variant).each do |ci|
        order.order_items.create!(
          product: ci.product, variant: ci.variant, supplier: ci.product.supplier,
          title: ci.display_title, sku: ci.variant&.sku,
          quantity: ci.quantity, unit_price_cents: ci.unit_price_cents
        )
      end
      order.log_event!("placed", "Order placed")
    end
  end

  # Clamped to what the account actually has and what the order can absorb —
  # never trust the checkbox's own dollar amount.
  def credit_to_apply(cart)
    return 0 unless current_user && ActiveModel::Type::Boolean.new.cast(params[:apply_credit])

    [current_user.store_credit_cents, cart.subtotal_cents].min
  end

  def capture_shipping(order, stripe_session)
    details = stripe_session.customer_details
    ship = stripe_session.try(:shipping_details) || stripe_session.try(:collected_information)&.try(:shipping_details)
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
      shipping_cents: stripe_session.try(:shipping_cost)&.try(:amount_total).to_i,
      tax_cents: stripe_session.try(:total_details)&.try(:amount_tax).to_i,
      total_cents: stripe_session.amount_total.to_i
    )
  end
end
