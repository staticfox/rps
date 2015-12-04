class DropUnusedTables < ActiveRecord::Migration
  def change
    drop_table :CommandServ_Commands
    drop_table :DNSServ_Exempt
  end
end
