class AddNameToApnApps < ActiveRecord::Migration
  def self.up
    add_column :apn_apps, :name, :string
  end

  def self.down
    remove_column :apn_apps, :name
  end
end