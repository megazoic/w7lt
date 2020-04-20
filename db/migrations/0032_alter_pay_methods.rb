Sequel.migration do
  change do
    alter_table(:payment_methods) do
      rename_column :method, :mode
    end
  end
end