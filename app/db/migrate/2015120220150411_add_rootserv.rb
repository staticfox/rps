class AddRootserv < ActiveRecord::Migration
  def change
    create_table :rootserv_accesses do |t|
      t.string :name
      t.string :flags
      t.string :added_by
      t.integer :added
      t.integer :modified
    end
  end
end
