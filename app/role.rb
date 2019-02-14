require_relative '../config/sequel'

module MemberTracker
  class Role < Sequel::Model
    many_to_many :auth_users, left_key: :role_id, right_key: :user_id, join_table: :roles_users
  end
end
