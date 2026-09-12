# Verified-purchase product reviews. Signed-in buyers land here straight from
# their orders; guests prove purchase via #verify/#locate first (mirrors
# OrdersController's number+email lookup), then follow a signed link per item
# built with Rails' built-in Signed Global ID — no separate token table.
class ReviewsController < ApplicationController
  before_action :set_order_item, only: %i[new create]
  before_action :authorize_reviewer!, only: %i[new create]
  before_action :redirect_if_already_reviewed, only: %i[new create]

  GUEST_TOKEN_PURPOSE = "guest_review"
  GUEST_TOKEN_TTL = 30.minutes

  def verify; end

  def locate
    order = Order.find_by(number: params[:number].to_s.strip.upcase)
    if order && order.customer_email.to_s.casecmp?(params[:email].to_s.strip)
      @order = order
      @reviewable_items = order.order_items.includes(:product, :review).reject { |i| i.review.present? || i.product.nil? }
      render :locate
    else
      redirect_to verify_reviews_path, alert: "No order matches that number and email."
    end
  end

  def new
    @review = Review.new
  end

  def create
    @review = Review.new(review_params)
    @review.order_item = @order_item
    @review.product = @order_item.product
    @review.user = current_user if current_user && @order_item.order.user_id == current_user.id
    @review.guest_email = @order_item.order.customer_email unless @review.user

    if @review.save
      redirect_to product_path(@order_item.product.slug), notice: "Thanks! Your review is awaiting approval."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def review_params
    params.require(:review).permit(:reviewer_name, :rating, :title, :body, photos: [])
  end

  def set_order_item
    @order_item = OrderItem.find(params[:order_item_id])
  end

  def redirect_if_already_reviewed
    return unless @order_item.review.present?

    redirect_to product_path(@order_item.product.slug), alert: "You've already reviewed this item."
  end

  def authorize_reviewer!
    return if current_user && @order_item.order.user_id == current_user.id
    return if valid_guest_token?

    redirect_to verify_reviews_path, alert: "Look up your order with its number and email to leave a review."
  end

  def valid_guest_token?
    token = params[:guest_token]
    return false if token.blank?

    record = GlobalID::Locator.locate_signed(token, for: GUEST_TOKEN_PURPOSE)
    record.is_a?(OrderItem) && record.id == @order_item.id
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
    false
  end

  helper_method :guest_review_token
  def guest_review_token(order_item)
    order_item.to_sgid(expires_in: GUEST_TOKEN_TTL, for: GUEST_TOKEN_PURPOSE).to_s
  end
end
