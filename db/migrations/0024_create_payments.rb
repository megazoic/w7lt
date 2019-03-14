Sequel.migration do
  up do
    #member_id, timestamp, payment_amount, payment_type (dues, donation_club_general, donation_repeater_fund, etc... DO YOU HAVE SUGGESTIONS?), payment_method (Paypal, personal check, cash, credit card), payment_agent (the person who handled the transaction, including Paypal)
    create_table(:payment_types) do
      primary_key :id, null: false
      String :type, null: false
    end
    create_table(:payment_methods) do
      primary_key :id, null: false
      String :method, null: false
    end
    create_table(:payments) do
      primary_key :id, null: false
      foreign_key :mbr_id, :members, null: false
      foreign_key :a_user_id, :auth_users, null: false
      foreign_key :payment_type_id, :payment_types, null: false
      foreign_key :payment_method_id, :payment_methods, null: false
      foreign_key :log_id, :logs
      Float :payment_amount, null: false
      DateTime :ts, null: false
    end
  end
  down do
    drop_table(:payments)
    drop_table(:payment_types)
    drop_table(:payment_methods)
  end
end