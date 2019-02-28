Sequel.migration do
  change do
    alter_table(:members) do
      add_column :mbr_since, Date
    end
  end
end