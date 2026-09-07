class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[google_oauth2]

  has_many :orders, dependent: :nullify
  has_many :tickets, dependent: :nullify

  def display_name = name.presence || email.split("@").first

  # Find-or-create a user from a Google OmniAuth payload. Links to an existing
  # account with the same email so email and Google logins share one account.
  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email)
    user ||= new(email: auth.info.email)

    user.provider = auth.provider
    user.uid = auth.uid
    user.name = user.name.presence || auth.info.name
    # OAuth users still need a password to satisfy Devise :validatable.
    user.password = Devise.friendly_token[0, 24] if user.new_record? || user.encrypted_password.blank?
    user.save!
    user
  end
end
