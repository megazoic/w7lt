Sequel.migration do
  change do
    alter_table(:logs) do
      add_foreign_key :unit_id, :units, null: true
    end
  end
end