class AddStoreCreditCentsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :store_credit_cents, :integer, null: false, default: 0
  end
end
