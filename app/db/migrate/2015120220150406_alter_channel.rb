class AlterChannel < ActiveRecord::Migration
  def change
    change_table :bot_channels do |t|
      t.integer :Options
    end

    change_table :channels do |t|
      t.string :Topic
    end
  end
end
