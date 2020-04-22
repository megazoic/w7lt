Sequel.migration do
  change do
    from(:members).where(mbr_type: nil).update(mbr_type: "none")
    alter_table(:members) do
      set_column_default :mbr_type, "none"
      set_column_not_null :mbr_type
    end
  end
end