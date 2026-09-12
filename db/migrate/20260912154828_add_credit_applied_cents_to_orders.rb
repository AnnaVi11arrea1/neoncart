class AddCreditAppliedCentsToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :credit_applied_cents, :integer, null: false, default: 0
  end
end
