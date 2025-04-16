require_relative '../config/sequel'
# member actions are things we need to track that require an action by a different member
# eg follow up phone call
module MemberTracker
  class MemberAction < Sequel::Model
    many_to_one :auth_user
    many_to_one :member_action_type
    many_to_one :member
  end
end
