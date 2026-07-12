# Cron (every 30 min): polls each supplier for shipments on in-flight
# orders, records them, and advances order status — which triggers the
# customer email + partner webhooks automatically.
class SyncTrackingJob < ApplicationJob
  queue_as :default

  def perform
    Order.needing_tracking_sync.find_each do |order|
      sync_order(order)
    end
  end

  private

  def sync_order(order)
    order.order_items.where(fulfillment_status: "submitted").group_by(&:supplier).each do |supplier, items|
      next unless supplier&.auto? && supplier.credentials_present?

      external_ids = items.map(&:external_order_id).compact.uniq
      external_ids.each do |ext_id|
        begin
          trackings = supplier.adapter_instance.fetch_tracking(ext_id)
        rescue Dropshipping::BaseAdapter::Error => e
          order.log_event!("error", "#{supplier.name} tracking sync: #{e.message.first(300)}")
          next
        end

        trackings.each do |t|
          next if t[:tracking_number].blank?

          shipment = order.shipments.find_or_initialize_by(tracking_number: t[:tracking_number])
          was_new = shipment.new_record?
          shipment.assign_attributes(
            supplier:, carrier: t[:carrier], tracking_url: t[:tracking_url],
            status: t[:delivered] ? "delivered" : "in_transit",
            shipped_at: shipment.shipped_at || Time.current,
            delivered_at: t[:delivered] ? (shipment.delivered_at || Time.current) : nil
          )
          shipment.save!

          if was_new
            OrderItem.where(id: items.map(&:id), external_order_id: ext_id).update_all(fulfillment_status: "fulfilled")
            order.mark_shipped!
          end
        end
      end
    end

    if order.shipped? && order.shipments.any? && order.shipments.all? { |s| s.status == "delivered" }
      order.mark_delivered!
    end
  end
end
