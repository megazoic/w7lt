Sequel.migration do
  change do
    alter_table(:unit_types) do
      add_column :a_user_id,Integer
    end
    from(:unit_types).where(a_user_id: nil).update(a_user_id: 22)
    alter_table(:unit_types) do
      set_column_not_null :a_user_id
      add_foreign_key [:a_user_id], :auth_users
    end
  end
end