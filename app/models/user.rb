class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :orders, dependent: :nullify
  has_many :tickets, dependent: :nullify

  def display_name = name.presence || email.split("@").first
end
