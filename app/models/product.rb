class Product < ApplicationRecord
  belongs_to :category, optional: true
  belongs_to :supplier, optional: true
  has_many :variants, -> { order(:position) }, dependent: :destroy
  has_many :product_images, -> { order(:position) }, dependent: :destroy
  has_many_attached :images

  accepts_nested_attributes_for :variants, allow_destroy: true, reject_if: :all_blank

  enum :status, { draft: "draft", active: "active", archived: "archived" }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug, on: :create

  scope :storefront, -> { active.order(featured: :desc, created_at: :desc) }

  def self.search(q)
    return all if q.blank?

    where("products.title ILIKE :q OR products.description ILIKE :q OR :plain = ANY(products.tags)",
          q: "%#{sanitize_sql_like(q)}%", plain: q.to_s.downcase)
  end

  def to_param = slug

  def manual? = supplier_id.nil?

  def display_price_cents(variant = nil)
    variant&.price_cents.presence || price_cents
  end

  def primary_image_url
    return Rails.application.routes.url_helpers.rails_blob_path(images.first, only_path: true) if images.attached?

    product_images.first&.remote_url
  end

  def all_image_urls
    urls = []
    if images.attached?
      urls += images.map { |i| Rails.application.routes.url_helpers.rails_blob_path(i, only_path: true) }
    end
    urls + product_images.map(&:remote_url).compact
  end

  private

  def generate_slug
    return if slug.present?

    base = title.to_s.parameterize
    candidate = base
    n = 1
    candidate = "#{base}-#{n += 1}" while self.class.exists?(slug: candidate)
    self.slug = candidate
  end
end
