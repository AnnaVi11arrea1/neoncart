module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end
      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: "bad_request", detail: e.message }, status: :bad_request
      end

      def ping
        render json: { ok: true, store: Rails.configuration.x.store_name, time: Time.current.iso8601 }
      end

      private

      attr_reader :current_api_key

      def authenticate_api_key!
        token = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
        @current_api_key = ApiKey.authenticate(token)
        render json: { error: "unauthorized" }, status: :unauthorized unless @current_api_key
      end

      def require_scope!(scope)
        return if current_api_key.scope?(scope)

        render json: { error: "forbidden", detail: "API key lacks scope #{scope}" }, status: :forbidden
      end
    end
  end
end
