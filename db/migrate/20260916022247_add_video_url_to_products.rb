class AddVideoUrlToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :video_url, :string
  end
end
