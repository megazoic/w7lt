Sequel.migration do
  change do
    alter_table(:roles) do
      add_column :desc, String 
    end
    alter_table(:auth_users) do
      add_column :time_pwd_set, DateTime
    end
  end
end