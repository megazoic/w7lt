Sequel.migration do
  change do
    drop_table(:rights)
    drop_table(:rights_roles)
  end
end