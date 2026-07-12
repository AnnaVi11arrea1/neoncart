class SyncAllProductsJob < ApplicationJob
  queue_as :default

  def perform
    Supplier.active.select(&:credentials_present?).each do |supplier|
      SyncProductsJob.perform_later(supplier.id)
    end
  end
end
