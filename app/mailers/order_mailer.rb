class OrderMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    mail(to: order.customer_email, subject: "Order #{order.number} confirmed ⚡")
  end

  def status_update(order)
    @order = order
    mail(to: order.customer_email, subject: "Order #{order.number} is now #{order.status}")
  end

  def shipped(order)
    @order = order
    @shipments = order.shipments
    mail(to: order.customer_email, subject: "Order #{order.number} has shipped 🚀")
  end
end
