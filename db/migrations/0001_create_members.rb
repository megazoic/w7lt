Sequel.migration do
  change do
    create_table :members do
      primary_key :id
      String :fname
      String :lname
    end
  end
end