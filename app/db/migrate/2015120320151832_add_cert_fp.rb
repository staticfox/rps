class AddCertFp < ActiveRecord::Migration
  def change
    change_table :users do |t|
      t.string :certfp
    end
  end
end
