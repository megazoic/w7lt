require_relative '../config/sequel'
module MemberTracker
  class Log < Sequel::Model
    many_to_one :action, :class=>Action, key: :action_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
  end
end
