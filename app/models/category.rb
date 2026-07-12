class Category < ApplicationRecord
  has_many :products, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation { self.slug = name.to_s.parameterize if slug.blank? }

  default_scope { order(:position, :name) }

  def to_param = slug
end
