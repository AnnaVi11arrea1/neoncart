# Fires after payment. Groups line items by supplier:
#  - auto suppliers: pushes the order via their adapter
#  - manual suppliers: flags items for the admin Fulfillment Queue
class SubmitOrderToSuppliersJob < ApplicationJob
  queue_as :default
  retry_on Dropshipping::BaseAdapter::Error, wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    order = Order.find(order_id)
    return unless order.paid?

    order.items_by_supplier.each do |supplier, items|
      if supplier.nil?
        # In-house / manual product — you ship it yourself.
        OrderItem.where(id: items.map(&:id)).update_all(fulfillment_status: "awaiting_manual")
      elsif supplier.manual? || !supplier.credentials_present?
        OrderItem.where(id: items.map(&:id)).update_all(fulfillment_status: "awaiting_manual")
        order.log_event!("note", "#{supplier.name}: queued for manual fulfillment")
      else
        begin
          external_id = supplier.adapter_instance.submit_order!(order, items)
          OrderItem.where(id: items.map(&:id)).update_all(fulfillment_status: "submitted", external_order_id: external_id)
          order.log_event!("submitted", "#{supplier.name}: order #{external_id} created", supplier: supplier.slug)
        rescue Dropshipping::BaseAdapter::Error => e
          order.log_event!("error", "#{supplier.name}: #{e.message.first(500)}")
          raise
        end
      end
    end

    order.mark_processing!
  end
end
