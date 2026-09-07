module Admin
  class SuppliersController < BaseController
    before_action :set_supplier, only: %i[edit update destroy sync test_connection import]

    def index
      @suppliers = Supplier.order(:name)
    end

    def new = @supplier = Supplier.new(fulfillment_mode: "manual")

    def create
      @supplier = Supplier.new(supplier_params)
      @supplier.save ? redirect_to(admin_suppliers_path, notice: "Supplier added.") : render(:new, status: :unprocessable_entity)
    end

    def edit; end

    def update
      @supplier.update(supplier_params) ? redirect_to(admin_suppliers_path, notice: "Saved.") : render(:edit, status: :unprocessable_entity)
    end

    def destroy
      @supplier.destroy!
      redirect_to admin_suppliers_path, notice: "Removed."
    end

    def sync
      SyncProductsJob.perform_later(@supplier.id)
      redirect_to admin_suppliers_path, notice: "#{@supplier.name}: sync queued. Refresh in a minute."
    end

    def test_connection
      @supplier.adapter_instance.test_connection!
      redirect_to admin_suppliers_path, notice: "#{@supplier.name}: connection OK ✓"
    rescue Dropshipping::BaseAdapter::Error => e
      redirect_to admin_suppliers_path, alert: "#{@supplier.name}: #{e.message}"
    end

    # Upload a supplier product export (currently ArtsAdd's .xls) and upsert
    # products. Re-uploading a fresh export pulls in changes.
    def import
      adapter = @supplier.adapter_instance
      unless adapter.respond_to?(:import_file!)
        return redirect_to edit_admin_supplier_path(@supplier),
                           alert: "#{@supplier.name} doesn't support file import."
      end

      file = params[:file]
      if file.blank?
        return redirect_to edit_admin_supplier_path(@supplier), alert: "Choose an export file to import."
      end

      count = adapter.import_file!(file.tempfile)
      @supplier.update!(last_synced_at: Time.current,
                        last_sync_log: "OK — imported #{count} products from file #{Time.current.strftime('%b %-d, %H:%M')}")
      redirect_to admin_suppliers_path,
                  notice: "#{@supplier.name}: imported #{count} products. New items are drafts — review pricing and activate."
    rescue Dropshipping::BaseAdapter::Error => e
      redirect_to edit_admin_supplier_path(@supplier), alert: "Import failed: #{e.message}"
    end

    private

    def set_supplier = @supplier = Supplier.find_by!(slug: params[:id])

    def supplier_params
      p = params.require(:supplier).permit(:name, :adapter, :api_base_url, :api_key, :api_secret,
                                           :shop_id, :active, :fulfillment_mode, :settings_json)
      if p.key?(:settings_json)
        raw = p.delete(:settings_json)
        p[:settings] = raw.present? ? JSON.parse(raw) : {}
      end
      p
    rescue JSON::ParserError
      params.require(:supplier).permit(:name, :adapter, :api_base_url, :api_key, :api_secret, :shop_id, :active, :fulfillment_mode)
    end
  end
end
