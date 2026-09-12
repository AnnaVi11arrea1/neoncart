# Immutable audit log behind User#store_credit_cents. Never written to
# directly — always through User#add_credit! so the running balance can't
# drift from this ledger.
class StoreCreditTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :order, optional: true

  KINDS = %w[earned redeemed adjusted].freeze
  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
