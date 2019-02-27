Sequel.migration do
  change do
    create_table :logs do
      primary_key :id
      foreign_key :mbr_id, :members
      foreign_key :a_user_id, :auth_users
      DateTime :ts, null: false
      String :notes
      Float :hours
    end
    create_table :actions do
      primary_key :id
      String :type
      String :description
    end
    create_table :logs_actions, id: false do
      foreign_key :action_id, :actions
      foreign_key :log_id, :logs
    end
  end
end