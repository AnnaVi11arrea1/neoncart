class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[google_oauth2]

  has_many :orders, dependent: :nullify
  has_many :tickets, dependent: :nullify
  has_many :favorites, dependent: :destroy
  has_many :favorite_products, through: :favorites, source: :product
  has_many :reviews, dependent: :nullify
  has_many :store_credit_transactions, dependent: :destroy

  # $5 off for creating an account — shown on the cart page to guest
  # checkouts. Fires for every brand-new account regardless of how they
  # signed up (email or Google), but from_omniauth reuses an existing
  # record when the email already has one, so linking Google to an old
  # account never double-grants this.
  WELCOME_CREDIT_CENTS = 500

  after_create :grant_welcome_credit!

  def display_name = name.presence || email.split("@").first

  # The only place store_credit_cents is ever written — keeps the running
  # balance in lockstep with the StoreCreditTransaction ledger. Positive
  # cents earns credit, negative redeems it.
  def add_credit!(cents, kind:, order: nil, note: nil)
    return if cents.zero?

    transaction do
      store_credit_transactions.create!(amount_cents: cents, kind:, order:, note:)
      increment!(:store_credit_cents, cents)
    end
  end

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

  private

  def grant_welcome_credit!
    add_credit!(WELCOME_CREDIT_CENTS, kind: "earned", note: "Welcome bonus for creating an account")
  end
end
