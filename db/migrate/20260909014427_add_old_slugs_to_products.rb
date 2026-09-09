class AddOldSlugsToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :old_slugs, :string, array: true, default: [], null: false
    add_index :products, :old_slugs, using: :gin
  end
end
