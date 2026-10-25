class AddGaIdsToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :ga_client_id, :string
    add_column :orders, :ga_session_id, :string
  end
end
