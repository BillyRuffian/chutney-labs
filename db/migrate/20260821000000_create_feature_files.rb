class CreateFeatureFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_files do |t|
      t.string :name, null: false
      t.text :content, null: false, default: ""

      t.timestamps
    end

    add_index :feature_files, :updated_at
  end
end
