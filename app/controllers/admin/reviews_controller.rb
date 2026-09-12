module Admin
  class ReviewsController < BaseController
    def index
      scope = Review.where(status: params[:status].presence || "pending").includes(:product, :user, :order_item).order(created_at: :desc)
      @pagy, @reviews = pagy(scope, limit: 30)
    end

    def approve
      Review.find(params[:id]).update!(status: "approved", rejection_reason: nil)
      redirect_to admin_reviews_path(status: params[:status]), notice: "Review approved."
    end

    def reject
      Review.find(params[:id]).update!(status: "rejected", rejection_reason: params[:rejection_reason].presence)
      redirect_to admin_reviews_path(status: params[:status]), notice: "Review rejected."
    end
  end
end
