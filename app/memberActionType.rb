require_relative '../config/sequel'

module MemberTracker
  class MemberActionType < Sequel::Model
    one_to_many :member_actions
  end
end
