Sequel.migration do
  change do
    create_table :roles_users, id: false do
      Integer :role_id
      Integer :user_id
    end
    create_table :rights_roles, id: false do
      Integer :role_id
    end
    create_table :roles do
      String :name
    end
    create_table :rights do
      String :name
    end
  end
end