class AddTopicData < ActiveRecord::Migration
  def change
    change_table :channels do |t|
      t.string :Topic_setat
      t.string :Topic_setby
    end
  end
end
