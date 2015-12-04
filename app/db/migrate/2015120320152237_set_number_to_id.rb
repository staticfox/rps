class SetNumberToId < ActiveRecord::Migration
  def change
    # channels
    rename_column :channels, :number, :id

    #bot channels
    rename_column :limit_serv_channels, :number, :id

    #channels
    rename_column :users, :Number, :id

    # user in channels
    rename_column :user_in_channels, :number, :id
  end
end
