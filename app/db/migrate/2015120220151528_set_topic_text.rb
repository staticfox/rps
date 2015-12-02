class SetTopicText < ActiveRecord::Migration
  def change
    change_column :channels, :Topic, :text
  end
end
