class DropFeatureFiles < ActiveRecord::Migration[8.1]
  def change
    drop_table :feature_files do |t|
      t.string :name, null: false
      t.text :content, null: false, default: ''
      t.timestamps
      t.index :updated_at
    end
  end
end
