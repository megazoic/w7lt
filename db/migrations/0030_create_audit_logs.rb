Sequel.migration do
  change do
    create_table(:audit_logs) do
      primary_key :id, null: false
      foreign_key :a_user_id, :auth_users, null: false
      foreign_key :pay_id, :payments, null: true
      foreign_key :mbr_id, :members, null: true
      foreign_key :unit_id, :units, null: true
      String :column, null: false
      DateTime :changed_date, null: false
      String :old_value, null: false
      String :new_value, null: false
    end
  end
end
