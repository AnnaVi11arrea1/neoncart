class AddPrimaryImageIdToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :primary_image_id, :bigint
  end
end
