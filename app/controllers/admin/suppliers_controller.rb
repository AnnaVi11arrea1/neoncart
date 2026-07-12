module Admin
  class SuppliersController < BaseController
    before_action :set_supplier, only: %i[edit update destroy sync test_connection]

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
