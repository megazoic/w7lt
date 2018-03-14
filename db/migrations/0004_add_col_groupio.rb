Sequel.migration do
  change do
    alter_table(:members) do
      add_column :gio_id , Integer
      add_column :sota , Integer, default: 0
    end
  end
end