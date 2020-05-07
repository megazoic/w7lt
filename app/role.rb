require_relative '../config/sequel'
#roles auth_u mbr_mgr
#save the position of the lowest role in the Roles table for the administrator (highest authority)

module MemberTracker
  class Role < Sequel::Model
    #one_to_many :auth_users, left_key: :role_id, right_key: :user_id, join_table: :roles_users
    one_to_many :auth_users, key: :role_id
  end
end
