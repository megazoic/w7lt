Sequel.migration do
  change do
    create_table :auth_users do
      primary_key :id
      String :email
      String :password
    end
  end
end