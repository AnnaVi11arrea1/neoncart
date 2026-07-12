class SyncProductsJob < ApplicationJob
  queue_as :default

  def perform(supplier_id)
    supplier = Supplier.find(supplier_id)
    count = supplier.adapter_instance.sync_products!
    supplier.update!(last_synced_at: Time.current, last_sync_log: "OK — #{count} products synced")
  rescue Dropshipping::BaseAdapter::Error => e
    supplier.update!(last_sync_log: "FAILED — #{e.message.first(500)}")
  end
end
