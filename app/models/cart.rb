class Cart < ApplicationRecord
  belongs_to :user, optional: true
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  def add(product, variant: nil, quantity: 1)
    item = cart_items.find_or_initialize_by(product:, variant:)
    item.quantity = item.persisted? ? item.quantity + quantity : quantity
    item.save!
    item
  end

  def subtotal_cents
    cart_items.includes(:product, :variant).sum(&:line_total_cents)
  end

  def item_count = cart_items.sum(:quantity)
  def empty? = cart_items.none?
end
