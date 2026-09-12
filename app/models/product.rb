class Product < ApplicationRecord
  belongs_to :category, optional: true
  belongs_to :supplier, optional: true
  has_many :variants, -> { order(:position) }, dependent: :destroy
  has_many :product_images, -> { order(:position) }, dependent: :destroy
  has_many :reviews, dependent: :nullify
  has_many :favorites, dependent: :destroy
  has_many_attached :images
  has_rich_text :description

  accepts_nested_attributes_for :variants, allow_destroy: true, reject_if: :all_blank

  enum :status, { draft: "draft", active: "active", archived: "archived" }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug, on: :create

  scope :storefront, -> { active.order(featured: :desc, created_at: :desc) }

  # Every product card calls #primary_image_url, which looks at both image
  # sources. Load them up front — Neon is a ~30ms round trip from this box,
  # so the N+1 cost a 20-product grid 83 queries / 1.5s instead of 9 / 0.3s.
  scope :with_card_images, -> { with_attached_images.includes(:product_images) }

  def self.search(q)
    return all if q.blank?

    left_joins(:rich_text_description)
      .where("products.title ILIKE :q OR action_text_rich_texts.body ILIKE :q OR :plain = ANY(products.tags)",
             q: "%#{sanitize_sql_like(q)}%", plain: q.to_s.downcase)
  end

  def self.find_by_old_slug(slug)
    where("? = ANY (old_slugs)", slug).first
  end

  def self.unique_slug_for(title, except_id: nil)
    base = title.to_s.parameterize.presence || "product"
    scope = except_id ? where.not(id: except_id) : all
    candidate = base
    n = 1
    candidate = "#{base}-#{n += 1}" while scope.exists?(slug: candidate)
    candidate
  end

  def to_param = slug

  # Bring the URL in line with the current title (e.g. after a rename),
  # keeping the old one around so its links 301 instead of 404ing.
  def refresh_slug!
    candidate = self.class.unique_slug_for(title, except_id: id)
    return false if candidate == slug

    update!(old_slugs: (old_slugs + [slug]).uniq, slug: candidate)
    true
  end

  def manual? = supplier_id.nil?

  # Cached at read time — no counter-cache column needed at this volume.
  def average_rating
    reviews.visible.average(:rating)&.round(1)
  end

  def reviews_count = reviews.visible.count

  def display_price_cents(variant = nil)
    variant&.price_cents.presence || price_cents
  end

  # Attached images in display order: the admin-chosen primary image (if any
  # is still attached) first, then the rest in upload order.
  def ordered_images
    return [] unless images.attached?

    imgs = images.to_a
    primary = primary_image_id.present? && imgs.find { |i| i.id == primary_image_id }
    primary ? [primary, *imgs.reject { |i| i.id == primary_image_id }] : imgs
  end

  def primary_image_url
    return Rails.application.routes.url_helpers.rails_blob_path(ordered_images.first, only_path: true) if images.attached?

    product_images.first&.remote_url
  end

  def all_image_urls
    urls = ordered_images.map { |i| Rails.application.routes.url_helpers.rails_blob_path(i, only_path: true) }
    urls + product_images.map(&:remote_url).compact
  end

  # Descriptive alt text set at upload time (see ActiveStorage blob metadata)
  # beats a bare product title for image SEO — falls back to the title when
  # an image has none (e.g. remote supplier thumbnails).
  def primary_image_alt
    images.attached? ? (ordered_images.first.metadata["alt"].presence || title) : title
  end

  def gallery_images
    items = ordered_images.map { |i| { url: Rails.application.routes.url_helpers.rails_blob_path(i, only_path: true), alt: i.metadata["alt"].presence || title } }
    items + product_images.filter_map { |pi| { url: pi.remote_url, alt: title } if pi.remote_url.present? }
  end

  private

  def generate_slug
    return if slug.present?

    self.slug = self.class.unique_slug_for(title)
  end
end
