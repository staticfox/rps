class AddPrimaryKeys < ActiveRecord::Migration
  def change
    change_column :limit_serv_channels, :id, :primary_key
  end
end
