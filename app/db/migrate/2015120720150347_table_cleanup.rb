class TableCleanup < ActiveRecord::Migration
  def change
    drop_table :channels
    drop_table :user_in_channels
    drop_table :users
  end
end
