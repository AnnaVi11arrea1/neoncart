module Admin
  class WebhookEndpointsController < BaseController
    def index
      @endpoints = WebhookEndpoint.includes(:deliveries).order(:name)
      @recent_deliveries = WebhookDelivery.recent.includes(:webhook_endpoint).limit(20)
    end

    def create
      endpoint = WebhookEndpoint.new(endpoint_params)
      if endpoint.save
        redirect_to admin_webhook_endpoints_path, notice: "Endpoint added. Signing secret: #{endpoint.secret}"
      else
        redirect_to admin_webhook_endpoints_path, alert: endpoint.errors.full_messages.to_sentence
      end
    end

    def update
      endpoint = WebhookEndpoint.find(params[:id])
      endpoint.update!(active: params.dig(:webhook_endpoint, :active) == "1")
      redirect_to admin_webhook_endpoints_path, notice: "Updated."
    end

    def destroy
      WebhookEndpoint.find(params[:id]).destroy!
      redirect_to admin_webhook_endpoints_path, notice: "Removed."
    end

    private

    def endpoint_params
      params.require(:webhook_endpoint).permit(:name, :url, events: [])
    end
  end
end
