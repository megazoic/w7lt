Sequel.migration do
  change do
    create_table :auth_users do
      primary_key :id
      String :fname
      String :lname, null: false
      String :email, null: false
      String :password, null: false
      String :authority, null: false
    end
  end
end