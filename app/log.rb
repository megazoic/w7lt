require_relative '../config/sequel'
module MemberTracker
  class Log < Sequel::Model
    many_to_one :action, key: :action_id
    many_to_one :auth_user, key: :a_user_id
    many_to_one :member, key: :mbr_id
  end
end
