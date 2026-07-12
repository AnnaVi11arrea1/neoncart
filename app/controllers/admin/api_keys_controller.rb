module Admin
  class ApiKeysController < BaseController
    def index
      @api_keys = ApiKey.order(created_at: :desc)
      @new_token = flash[:new_token]
    end

    def create
      _key, raw = ApiKey.generate!(
        name: params.require(:api_key)[:name],
        partner_url: params[:api_key][:partner_url],
        scopes: Array(params[:api_key][:scopes]).select(&:present?)
      )
      flash[:new_token] = raw
      redirect_to admin_api_keys_path, notice: "Key created — copy the token now, it won't be shown again."
    end

    def destroy
      ApiKey.find(params[:id]).update!(active: false)
      redirect_to admin_api_keys_path, notice: "Key revoked."
    end
  end
end
