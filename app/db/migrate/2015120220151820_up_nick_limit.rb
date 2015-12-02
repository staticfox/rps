class UpNickLimit < ActiveRecord::Migration
  def change
    change_column :users, :Nick, :text
  end
end
