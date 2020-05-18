Sequel.migration do
  up do
    alter_table(:members) do
      add_column :ok_to_email, TrueClass, default: false
    end
    from(:members).update(ok_to_email: true)
    alter_table(:members) do
      set_column_not_null :ok_to_email
    end
  end
  down do
    alter_table(:members) do
      drop_column :ok_to_email
    end
  end
end