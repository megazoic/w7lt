Sequel.migration do
  change do
    alter_table(:unit_types) do
      rename_column :desc, :descr
    end
  end
end