Sequel.migration do
  up do
    alter_table(:members) do
      add_column :mbrship_renewal_halt, TrueClass, default: false
      add_column :mbrship_renewal_contacts, Integer, default: 0
      add_column :email_bogus, TrueClass, default: false
      add_column :mbrship_renewal_date, DateTime
      add_column :mbrship_renewal_active, TrueClass, default: false
    end
    from(:members).update(mbrship_renewal_halt: false)
    from(:members).update(mbrship_renewal_contacts: 0)
    from(:members).update(email_bogus: false)
    from(:members).update(mbrship_renewal_active: false)
    alter_table(:members) do
      #don't want mbrship_renewal_date to be 'not null' so non-members can go here
      set_column_not_null :mbrship_renewal_halt
      set_column_not_null :mbrship_renewal_contacts
      set_column_not_null :email_bogus
      set_column_not_null :mbrship_renewal_active
    end
  end
  down do
    alter_table(:members) do
      drop_column :mbrship_renewal_halt
      drop_column :mbrship_renewal_contacts
      drop_column :email_bogus
      drop_column :mbrship_renewal_date
      drop_column :mbrship_renewal_active
    end
  end
end