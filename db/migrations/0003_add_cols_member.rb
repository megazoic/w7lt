Sequel.migration do
  change do
    alter_table(:members) do
      add_column :phw , String 
      add_column :phw_pub, Integer, default: 0
      add_column :phh, String 
      add_column :phh_pub, Integer, default: 0
      add_column :phm, String 
      add_column :phm_pub, Integer, default: 0
      add_column :email, String 
      add_column :apt, String 
      add_column :city, String 
      add_column :street, String 
      add_column :zip, String 
      add_column :state, String 
      add_column :callsign, String 
      add_column :paid_up, Integer, default: 0
      add_column :arrl, Integer, default: 0
      add_column :ares, Integer, default: 0
      add_column :net, Integer, default: 0
      add_column :ve, Integer, default: 0
      add_column :elmer, Integer, default: 0
      add_column :arrl_expire, String    #"YYYY-MM-DD HH:MM:SS.SSS"
      add_column :license_class, String 
      add_column :mbr_type, String 
    end
  end
end
